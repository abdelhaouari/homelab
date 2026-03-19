# ============================================================
# outputs.tf — Post-deploy Information
# ============================================================
# Displays useful connection info after `terraform apply`.

output "vm_ips" {
  description = "Map of VM hostnames to their static IPs"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => var.vms[name].ip
  }
}

output "ssh_command" {
  description = "SSH commands to connect to each VM"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => "ssh labadmin@${split("/", var.vms[name].ip)[0]}"
  }
}
