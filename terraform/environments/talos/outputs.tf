# ==============================================================================
# outputs.tf - Useful outputs for Talos cluster management
# ==============================================================================

output "talos_vm_ids" {
  description = "Map of VM names to their Proxmox VM IDs"
  value = {
    for key, vm in proxmox_virtual_environment_vm.talos :
    key => vm.vm_id
  }
}

output "talos_nodes" {
  description = "Summary of deployed Talos nodes"
  value = {
    for key, vm_def in var.talos_vms :
    key => {
      hostname = vm_def.hostname
      ip       = vm_def.ip
      role     = contains(vm_def.tags, "controlplane") ? "control-plane" : "worker"
    }
  }
}
