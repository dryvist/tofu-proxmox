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
  username                 = var.PKR_PVE_USERNAME
  token                    = var.PROXMOX_TOKEN
  node                     = var.PROXMOX_VE_NODE
  insecure_skip_tls_verify = var.PROXMOX_VE_INSECURE == "true"

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
    type      = "sata"
    iso_file  = "${var.iso_storage_pool}:iso/${local.images.win10.iso}"
    unmount   = true
  }

  # Packer builds this ISO from the rendered answer files and removes it after
  # the build. Nothing is staged on a hypervisor by hand.
  additional_iso_files {
    type    = "sata"
    index   = "1"
    unmount = true
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
  username                 = var.PKR_PVE_USERNAME
  token                    = var.PROXMOX_TOKEN
  node                     = var.PROXMOX_VE_NODE
  insecure_skip_tls_verify = var.PROXMOX_VE_INSECURE == "true"

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
  username                 = var.PKR_PVE_USERNAME
  token                    = var.PROXMOX_TOKEN
  node                     = var.PROXMOX_VE_NODE
  insecure_skip_tls_verify = var.PROXMOX_VE_INSECURE == "true"

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

  # Generalize last. /quiet suppresses the interactive dialog, /shutdown leaves
  # the VM off so Packer can convert it to a template cleanly.
  provisioner "powershell" {
    inline = [
      "& C:\\Windows\\System32\\Sysprep\\sysprep.exe /generalize /oobe /shutdown /quiet /unattend:C:\\Windows\\Panther\\unattend.xml",
    ]
    # sysprep terminates the WinRM session as it shuts the guest down; that is
    # the expected end of the build, not a failure.
    valid_exit_codes = [0, 1, 2300218]
  }
}
