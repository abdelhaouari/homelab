# ============================================================
# ubuntu-cloud.pkr.hcl — Ubuntu 24.04 Golden Image Builder
# ============================================================
# Builds a hardened Ubuntu 24.04 template on Proxmox via autoinstall.
# Autoinstall config is injected as a mounted ISO (air-gapped, no HTTP dependency).
#
# Usage:
#   packer init .
#   packer validate -var-file=credentials.pkrvars.hcl .
#   packer build -var-file=credentials.pkrvars.hcl .

packer {
  required_plugins {
    proxmox = {
      version = "~> 1"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# -----------------------------------------------
# Source: Proxmox ISO Builder
# -----------------------------------------------
source "proxmox-iso" "ubuntu" {

  # --- Proxmox API Connection ---
  proxmox_url              = var.proxmox_api_url
  username                 = var.proxmox_api_token_id
  token                    = var.proxmox_api_token_secret
  insecure_skip_tls_verify = true

  # --- VM Identity ---
  vm_name = var.vm_name
  vm_id   = var.vm_id
  node    = var.proxmox_node

  # --- Template Output ---
  template_name        = var.template_name
  template_description = "Ubuntu 24.04 Golden Image - built by Packer"

  # --- Hardware ---
  cpu_type        = "x86-64-v2-AES"
  cores           = 2
  memory          = 2048
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true

  disks {
    disk_size    = "20G"
    type         = "scsi"
    storage_pool = "local-zfs"
    format       = "raw"
  }

  # --- Network ---
  network_adapters {
    model    = "virtio"
    bridge   = var.network_bridge
    vlan_tag = var.vlan_tag
  }

  # --- Boot ISO (Ubuntu Installer) ---
  boot_iso {
    type         = "ide"
    index        = "2"
    iso_file     = "local:iso/ubuntu-24.04.3-live-server-amd64.iso"
    iso_checksum = "file:https://releases.ubuntu.com/24.04/SHA256SUMS"
    unmount      = true
  }

  # --- Cloud-Init (enabled on final template) ---
  cloud_init              = true
  cloud_init_storage_pool = "local-zfs"

  # --- SSH Communication ---
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "30m"

  # --- Autoinstall Injection (Air-Gapped via mounted ISO) ---
  # Eliminates HTTP dependency — autoinstall files are served as a
  # mounted CD-ROM with the "cidata" label, which cloud-init/nocloud
  # detects automatically. More secure than HTTP (no password hash
  # transiting the network).
  additional_iso_files {
    type             = "ide"
    index            = "3"
    cd_files         = ["./http/user-data", "./http/meta-data"]
    cd_label         = "cidata"
    iso_storage_pool = "local"
    unmount          = true
  }

  # --- Boot Command (GRUB edit method) ---
  # Edits the default GRUB entry to append autoinstall parameters,
  # pointing to the nocloud datasource on the mounted cidata ISO.
  boot_wait = "10s"
  boot_command = [
    "e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud;",
    "<f10>"
  ]
}

# -----------------------------------------------
# Build and Provisioning
# -----------------------------------------------
build {
  name    = "ubuntu-golden"
  sources = ["source.proxmox-iso.ubuntu"]

  # --- OS Hardening and Cleanup ---
  provisioner "shell" {
    inline = [
      # 1. Lock the build user password (forces SSH key-only auth)
      "sudo passwd -l labadmin",

      # 2. Harden SSH: disable password authentication entirely
      "sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config",

      # 3. Remove the temporary build SSH authorized keys (if any)
      "rm -f ~/.ssh/authorized_keys",

      # 4. Clean apt cache (reduce image size)
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",

      # 5. Cloud-Init cleanup (critical for templates)
      # Ensures cloned VMs regenerate unique SSH host keys, machine-id, and network config
      "sudo cloud-init clean",

      # 6. Clear machine-id (prevents DHCP IP conflicts across clones)
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",

      # 7. Clear shell history (no build artifacts left in the template)
      "sudo rm -f /root/.bash_history",
      "rm -f ~/.bash_history",

      # 8. Remove passwordless sudo scaffolding (Critical Security Step)
      "sudo rm -f /etc/sudoers.d/labadmin"
    ]
  }
}