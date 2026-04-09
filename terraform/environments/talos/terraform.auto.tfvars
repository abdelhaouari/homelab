# ==============================================================================
# terraform.auto.tfvars - Non-sensitive default values for Talos cluster
# ==============================================================================

proxmox_api_url = "https://192.168.0.199:8006"
proxmox_node    = "pve"
talos_image_id  = "local:iso/talos-v1.12.6-nocloud-amd64.img"

# --- Talos VM Definitions ---
# Same IPs as the former Ubuntu VMs on VLAN 20.
# Control plane needs 4GB RAM for etcd + API server + controller-manager + scheduler.

talos_vms = {
  ctrl-01 = {
    vm_id     = 201
    hostname  = "talos-ctrl-01"
    ip        = "10.10.20.10"
    cores     = 2
    memory    = 4096
    disk_size = 20
    tags      = ["kubernetes", "controlplane", "terraform"]
  }
  work-01 = {
    vm_id     = 202
    hostname  = "talos-work-01"
    ip        = "10.10.20.11"
    cores     = 2
    memory    = 6144
    disk_size = 20
    tags      = ["kubernetes", "worker", "terraform"]
  }
  work-02 = {
    vm_id     = 203
    hostname  = "talos-work-02"
    ip        = "10.10.20.12"
    cores     = 2
    memory    = 6144
    disk_size = 20
    tags      = ["kubernetes", "worker", "terraform"]
  }
  work-03 = {
    vm_id     = 204
    hostname  = "talos-work-03"
    ip        = "10.10.20.13"
    cores     = 2
    memory    = 6144
    disk_size = 20
    tags      = ["kubernetes", "worker", "terraform"]
  }
}
