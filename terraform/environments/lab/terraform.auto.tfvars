# ============================================================
# terraform.auto.tfvars — Non-sensitive environment values
# ============================================================
# Auto-loaded by Terraform. Secrets are in credentials.auto.tfvars.

proxmox_node    = "pve"
template_id     = 9000
default_gateway = "10.10.20.1"
dns_server      = "10.10.20.1"

# --- VM Definitions ---
# Each entry creates a full clone of the golden image template.
# IPs are static (injected via Cloud-Init), all on VLAN 20 (Kubernetes).

vms = {
  k8s-ctrl-01 = {
    vm_id    = 101
    hostname = "k8s-ctrl-01"
    cores    = 2
    memory   = 4096
    disk     = "20G"
    ip       = "10.10.20.10/24"
    tags     = ["kubernetes", "control-plane"]
  }

  k8s-work-01 = {
    vm_id    = 102
    hostname = "k8s-work-01"
    cores    = 2
    memory   = 4096
    disk     = "20G"
    ip       = "10.10.20.11/24"
    tags     = ["kubernetes", "worker"]
  }

  k8s-work-02 = {
    vm_id    = 103
    hostname = "k8s-work-02"
    cores    = 2
    memory   = 4096
    disk     = "20G"
    ip       = "10.10.20.12/24"
    tags     = ["kubernetes", "worker"]
  }
}
