packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

locals {
  proxmox_url = "${var.PROXMOX_VE_ENDPOINT}/api2/json"

  # OpenBao stores one field, `user@realm!tokenid=secret`, while the builder
  # wants the identity and the secret separately. Split on the FIRST `=` only:
  # the secret half is a UUID today, but nothing guarantees a token secret
  # contains no `=`, and splitting on the last one would corrupt it silently.
  pve_username = split("=", var.PROXMOX_VE_API_TOKEN)[0]
  pve_token    = trimprefix(var.PROXMOX_VE_API_TOKEN, "${local.pve_username}=")

  # Per-OS facts. The WIM indices were read off the actual ISOs with `wiminfo`
  # rather than assumed - an index that names the wrong edition installs a
  # silently different OS, and Home editions cannot accept incoming RDP at all.
  #   Windows10.iso          index 6 = Windows 10 Pro
  #   Windows11.iso          index 6 = Windows 11 Pro
  #   WindowsServer2025.iso  index 4 = SERVERDATACENTER (full desktop, not Core)
  # vioscsi_path is the driver directory inside virtio-win.iso; the subdirectory
  # names are the virtio project's own (w10, w11, 2k25), not Proxmox's ostype.
  images = {
    win10 = {
      vm_id         = 9210
      iso           = "Windows10.iso"
      wim_index     = 6
      vioscsi_path  = "vioscsi\\w10\\amd64"
      ostype        = "win10"
      computer_name = "WIN10-TMPL"
      description   = "Windows 10 Pro template - sysprep generalized"
    }
    win11 = {
      vm_id         = 9211
      iso           = "Windows11.iso"
      wim_index     = 6
      vioscsi_path  = "vioscsi\\w11\\amd64"
      ostype        = "win11"
      computer_name = "WIN11-TMPL"
      description   = "Windows 11 Pro template - sysprep generalized"
    }
    win25 = {
      vm_id         = 9212
      iso           = "WindowsServer2025.iso"
      wim_index     = 4
      vioscsi_path  = "vioscsi\\2k25\\amd64"
      ostype        = "win11"
      computer_name = "WIN25-TMPL"
      description   = "Windows Server 2025 Datacenter template - sysprep generalized"
    }
  }
}

# One source per OS. The three differ only by the locals above, but Packer
# cannot iterate source blocks, and overriding a nested additional_iso_files
# block from inside `build` is not reliable - so each source is written out and
# every value that can come from locals does.
source "proxmox-iso" "win10" {
  proxmox_url              = local.proxmox_url
  username                 = local.pve_username
  token                    = local.pve_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = var.PROXMOX_VE_INSECURE == "true"

  # Default is 1m, which a Windows guest shutdown routinely exceeds - and the
  # shutdown is a Proxmox task the plugin waits on before converting.
  task_timeout = "20m"

  vm_id                = local.images.win10.vm_id
  vm_name              = "win10-template"
  template_name        = "win10-template"
  template_description = local.images.win10.description
  os                   = local.images.win10.ostype

  bios = "ovmf"
  efi_config {
    efi_storage_pool  = var.vm_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  # Windows 10 does not require a TPM, but the deployment object gives every
  # win-vdi guest a tpm_state. Building the template without one would make the
  # clone differ from its template on a ForceNew-adjacent attribute and show a
  # diff on every plan.
  tpm_config {
    tpm_storage_pool = var.vm_storage_pool
    tpm_version      = "v2.0"
  }

  cpu_type        = "host"
  cores           = 4
  memory          = 8192
  scsi_controller = "virtio-scsi-pci"

  disks {
    type         = "scsi"
    disk_size    = "64G"
    storage_pool = var.vm_storage_pool
    format       = "raw"
  }

  network_adapters {
    bridge   = var.bridge
    model    = "virtio"
    vlan_tag = var.vlan_tag
  }

  boot_iso {
    type     = "sata"
    iso_file = "${var.iso_storage_pool}:iso/${local.images.win10.iso}"
    unmount  = true
  }

  # Packer builds this ISO from the rendered answer files and removes it after
  # the build. Nothing is staged on a hypervisor by hand.
  additional_iso_files {
    type     = "sata"
    index    = "1"
    unmount  = true
    cd_label = "UNATTEND"
    cd_content = {
      "autounattend.xml" = templatefile("${path.root}/answer/autounattend.pkrtpl.xml", {
        admin_password = var.WINDOWS_ADMIN_PASSWORD
        wim_index      = local.images.win10.wim_index
        vioscsi_path   = local.images.win10.vioscsi_path
        computer_name  = local.images.win10.computer_name
      })
      "oobe-unattend.xml" = templatefile("${path.root}/answer/oobe-unattend.pkrtpl.xml", {
        admin_password = var.WINDOWS_ADMIN_PASSWORD
      })
    }
    iso_storage_pool = var.iso_storage_pool
  }

  additional_iso_files {
    type     = "sata"
    index    = "2"
    iso_file = "${var.iso_storage_pool}:iso/virtio-win.iso"
    unmount  = true
  }

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.WINDOWS_ADMIN_PASSWORD
  winrm_timeout  = "60m"
  winrm_use_ssl  = false
  winrm_insecure = true
}

source "proxmox-iso" "win11" {
  proxmox_url              = local.proxmox_url
  username                 = local.pve_username
  token                    = local.pve_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = var.PROXMOX_VE_INSECURE == "true"

  # Default is 1m, which a Windows guest shutdown routinely exceeds - and the
  # shutdown is a Proxmox task the plugin waits on before converting.
  task_timeout = "20m"

  vm_id                = local.images.win11.vm_id
  vm_name              = "win11-template"
  template_name        = "win11-template"
  template_description = local.images.win11.description
  os                   = local.images.win11.ostype

  bios = "ovmf"
  efi_config {
    efi_storage_pool  = var.vm_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  # Windows 11 refuses to install without a TPM. The answer file also sets
  # BypassTPMCheck, but a real vTPM is the supported path and keeps BitLocker
  # and Secure Boot available to the clones.
  tpm_config {
    tpm_storage_pool = var.vm_storage_pool
    tpm_version      = "v2.0"
  }

  cpu_type        = "host"
  cores           = 8
  memory          = 12288
  scsi_controller = "virtio-scsi-pci"

  disks {
    type         = "scsi"
    disk_size    = "64G"
    storage_pool = var.vm_storage_pool
    format       = "raw"
  }

  network_adapters {
    bridge   = var.bridge
    model    = "virtio"
    vlan_tag = var.vlan_tag
  }

  boot_iso {
    type     = "sata"
    iso_file = "${var.iso_storage_pool}:iso/${local.images.win11.iso}"
    unmount  = true
  }

  additional_iso_files {
    type     = "sata"
    index    = "1"
    unmount  = true
    cd_label = "UNATTEND"
    cd_content = {
      "autounattend.xml" = templatefile("${path.root}/answer/autounattend.pkrtpl.xml", {
        admin_password = var.WINDOWS_ADMIN_PASSWORD
        wim_index      = local.images.win11.wim_index
        vioscsi_path   = local.images.win11.vioscsi_path
        computer_name  = local.images.win11.computer_name
      })
      "oobe-unattend.xml" = templatefile("${path.root}/answer/oobe-unattend.pkrtpl.xml", {
        admin_password = var.WINDOWS_ADMIN_PASSWORD
      })
    }
    iso_storage_pool = var.iso_storage_pool
  }

  additional_iso_files {
    type     = "sata"
    index    = "2"
    iso_file = "${var.iso_storage_pool}:iso/virtio-win.iso"
    unmount  = true
  }

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.WINDOWS_ADMIN_PASSWORD
  winrm_timeout  = "60m"
  winrm_use_ssl  = false
  winrm_insecure = true
}

source "proxmox-iso" "win25" {
  proxmox_url              = local.proxmox_url
  username                 = local.pve_username
  token                    = local.pve_token
  node                     = var.proxmox_node
  insecure_skip_tls_verify = var.PROXMOX_VE_INSECURE == "true"

  # Default is 1m, which a Windows guest shutdown routinely exceeds - and the
  # shutdown is a Proxmox task the plugin waits on before converting.
  task_timeout = "20m"

  vm_id                = local.images.win25.vm_id
  vm_name              = "win25-template"
  template_name        = "win25-template"
  template_description = local.images.win25.description
  os                   = local.images.win25.ostype

  bios = "ovmf"
  efi_config {
    efi_storage_pool  = var.vm_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  tpm_config {
    tpm_storage_pool = var.vm_storage_pool
    tpm_version      = "v2.0"
  }

  cpu_type        = "host"
  cores           = 8
  memory          = 12288
  scsi_controller = "virtio-scsi-pci"

  disks {
    type         = "scsi"
    disk_size    = "64G"
    storage_pool = var.vm_storage_pool
    format       = "raw"
  }

  network_adapters {
    bridge   = var.bridge
    model    = "virtio"
    vlan_tag = var.vlan_tag
  }

  boot_iso {
    type     = "sata"
    iso_file = "${var.iso_storage_pool}:iso/${local.images.win25.iso}"
    unmount  = true
  }

  additional_iso_files {
    type     = "sata"
    index    = "1"
    unmount  = true
    cd_label = "UNATTEND"
    cd_content = {
      "autounattend.xml" = templatefile("${path.root}/answer/autounattend.pkrtpl.xml", {
        admin_password = var.WINDOWS_ADMIN_PASSWORD
        wim_index      = local.images.win25.wim_index
        vioscsi_path   = local.images.win25.vioscsi_path
        computer_name  = local.images.win25.computer_name
      })
      "oobe-unattend.xml" = templatefile("${path.root}/answer/oobe-unattend.pkrtpl.xml", {
        admin_password = var.WINDOWS_ADMIN_PASSWORD
      })
    }
    iso_storage_pool = var.iso_storage_pool
  }

  additional_iso_files {
    type     = "sata"
    index    = "2"
    iso_file = "${var.iso_storage_pool}:iso/virtio-win.iso"
    unmount  = true
  }

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.WINDOWS_ADMIN_PASSWORD
  winrm_timeout  = "60m"
  winrm_use_ssl  = false
  winrm_insecure = true
}

build {
  name = "windows-templates"
  sources = [
    "source.proxmox-iso.win10",
    "source.proxmox-iso.win11",
    "source.proxmox-iso.win25",
  ]

  # Stage the post-sysprep answer file where Windows looks for it on the first
  # boot of a clone. Copied from the attached answer disc rather than uploaded,
  # so the password never crosses the WinRM channel a second time.
  provisioner "powershell" {
    inline = [
      "$src = Get-ChildItem -Path (Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { \"$($_.DriveLetter):\\oobe-unattend.xml\" }) -ErrorAction SilentlyContinue | Select-Object -First 1",
      "if (-not $src) { throw 'oobe-unattend.xml not found on any attached volume' }",
      "New-Item -ItemType Directory -Force -Path 'C:\\Windows\\Panther' | Out-Null",
      "Copy-Item -Path $src.FullName -Destination 'C:\\Windows\\Panther\\unattend.xml' -Force",
      "Write-Host \"staged $($src.FullName) -> C:\\Windows\\Panther\\unattend.xml\"",
    ]
  }

  # Fail the build here rather than ship a template whose clones cannot be
  # reached. A missing guest agent would also make every later Terraform plan
  # stall for the module's full 15-minute agent timeout.
  provisioner "powershell" {
    inline = [
      "$svc = Get-Service -Name QEMU-GA -ErrorAction SilentlyContinue",
      "if (-not $svc) { throw 'qemu-guest-agent is not installed - virtio-win-guest-tools did not run' }",
      "Write-Host \"qemu-guest-agent: $($svc.Status)\"",
      "if (-not (Get-NetAdapter | Where-Object Status -eq 'Up')) { throw 'no network adapter is up - NetKVM missing' }",
    ]
  }

  # Generalize last. /quit, NOT /shutdown: this builder has no shutdown_command
  # and always powers the guest off itself, via
  # stepConvertToTemplate -> ShutdownVm -> POST /status/shutdown. Proxmox
  # answers that with an error on a VM that is already stopped, the plugin
  # retries three times and then halts with "could not stop" - so letting
  # sysprep power the guest off races the builder and loses the whole build at
  # its last step. /quit leaves the guest generalized and running; the very next
  # thing that happens to it is the builder's own clean shutdown.
  provisioner "powershell" {
    # sysprep.exe is a GUI-subsystem binary, so `&` does not block on it: the
    # provisioner would return while generalization was still running and the
    # builder would cut power mid-flight, producing a template that converts
    # cleanly and misbehaves at OOBE. Start-Process -Wait, then poll ImageState
    # until Windows itself reports the reseal is finished.
    inline = [
      "Start-Process -FilePath C:\\Windows\\System32\\Sysprep\\sysprep.exe -Wait -NoNewWindow -ArgumentList '/generalize','/oobe','/quit','/quiet','/unattend:C:\\Windows\\Panther\\unattend.xml'",
      "$state = 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State'",
      "$deadline = (Get-Date).AddMinutes(20)",
      "while ((Get-ItemProperty $state).ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {",
      "  if ((Get-Date) -gt $deadline) {",
      "    foreach ($log in 'setupact.log','setuperr.log') {",
      "      $p = \"C:\\Windows\\System32\\Sysprep\\Panther\\$log\"",
      "      if (Test-Path $p) { Write-Host \"--- $log ---\"; Get-Content $p -Tail 80 }",
      "    }",
      "    throw \"sysprep did not reach RESEAL_TO_OOBE within 20m (ImageState=$((Get-ItemProperty $state).ImageState))\"",
      "  }",
      "  Start-Sleep -Seconds 10",
      "}",
      "Write-Host 'sysprep generalize complete - builder will power the guest off'",
    ]
  }
}
