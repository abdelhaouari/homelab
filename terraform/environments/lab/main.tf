# ============================================================
# main.tf — VM Provisioning from Golden Image Template
# ============================================================
# Creates VMs by cloning the Packer-built template (ID 9000).
# Each VM gets a static IP, SSH key, and hostname via Cloud-Init.
# Uses for_each over the `vms` variable map for DRY configuration.

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  # --- VM Identity ---
  name        = each.value.hostname
  vm_id       = each.value.vm_id
  node_name   = var.proxmox_node
  description = "Provisioned by Terraform from golden image template ${var.template_id}"
  tags        = each.value.tags

  # --- Clone from Packer Template ---
  clone {
    vm_id = var.template_id
    full  = true
  }

  # --- Hardware ---
  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  # --- Network ---
  network_device {
    model   = "virtio"
    bridge  = "vmbr1"
    vlan_id = 20
  }

  # --- Cloud-Init Configuration ---
  # This is the handoff from Packer -> Terraform:
  # The template has cloud-init installed and enabled.
  # Terraform injects the runtime configuration at first boot.
  initialization {
    datastore_id = "local-zfs"
    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.default_gateway
      }
    }

    dns {
      servers = [var.dns_server]
    }

    user_account {
      username = "labadmin"
      keys     = [var.ssh_public_key]
    }
  }

  # --- Agent ---
  agent {
    enabled = true
  }

  # --- Boot Order ---
  boot_order = ["scsi0"]

  # --- Lifecycle ---
  # Prevent Terraform from recreating VMs on Cloud-Init changes
  # (use `terraform taint` to force rebuild if needed)
  lifecycle {
    ignore_changes = [
      initialization,
    ]
  }
}
