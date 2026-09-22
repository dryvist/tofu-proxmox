## template:jinja
#cloud-config
# Managed by tofu-proxmox ssh-ca-trust.tf — mirrors the ansible-proxmox-apps
# ssh_ca_trust role's sshd drop-in shape (principal debian: [ansible, semaphore]).
# First-boot only; Ansible re-verifies and owns this file post-boot the same
# way it owns every other guest running OpenBao SSH-CA trust.
write_files:
  - path: ${ca_file}
    owner: root:root
    permissions: '0644'
    content: |
      ${indent(6, ca_public_key)}

  - path: ${principals_dir}/debian
    owner: root:root
    permissions: '0644'
    content: |
      ansible
      semaphore

  - path: ${sshd_dropin}
    owner: root:root
    permissions: '0644'
    content: |
      # Managed by tofu-proxmox ssh-ca-trust.tf — OpenBao SSH client CA trust,
      # baked in at first boot. Late-numbered to win merges.
      TrustedUserCAKeys ${ca_file}
      AuthorizedPrincipalsFile ${principals_dir}/%u

runcmd:
  - mkdir -p ${principals_dir}
  - systemctl reload sshd || systemctl reload ssh || true
