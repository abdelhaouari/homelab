# ==============================================================================
# main.tf - Talos Linux VM provisioning on Proxmox
# ==============================================================================
# Unlike Ubuntu VMs (Phase 2), Talos VMs do NOT use:
#   - clone {} block (no template — we import a raw disk image directly)
#   - initialization {} block (no Cloud-Init — Talos uses its own API on port 50000)
#   - QEMU Guest Agent (Talos is immutable — no guest agent available)
# ==============================================================================

resource "proxmox_virtual_environment_vm" "talos" {
  for_each = var.talos_vms

  name        = each.value.hostname
  vm_id       = each.value.vm_id
  node_name   = var.proxmox_node
  description = "Talos Linux node - Managed by Terraform"
  tags        = each.value.tags
  on_boot     = true

  # Talos has no QEMU Guest Agent — disable to avoid Proxmox timeout waiting for it
  agent {
    enabled = false
  }

  # Talos cannot receive ACPI shutdown signals without a guest agent.
  # Without this, terraform destroy hangs indefinitely waiting for a graceful shutdown.
  stop_on_destroy = true

  operating_system {
    type = "l26"
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  scsi_hardware = "virtio-scsi-single"

  # Boot disk — imported from the Talos nocloud raw image
  disk {
    datastore_id = "local-zfs"
    file_id      = var.talos_image_id
    interface    = "scsi0"
    discard      = "on"
    size         = each.value.disk_size
    file_format  = "raw"
  }

  network_device {
    model   = "virtio"
    bridge  = "vmbr1"
    vlan_id = 20
  }

  # Serial console for Talos debug output (visible in Proxmox console → xterm.js)
  serial_device {}

  boot_order = ["scsi0"]

  # After initial import, the file_id is no longer relevant.
  # Prevents VM recreation if the source image is removed from Proxmox.
  lifecycle {
    ignore_changes = [disk[0].file_id]
  }
}
