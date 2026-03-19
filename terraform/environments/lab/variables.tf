# ============================================================
# variables.tf — Variable Declarations
# ============================================================
# Sensitive values are loaded from credentials.auto.tfvars (excluded from Git).
# Non-sensitive defaults are in terraform.auto.tfvars (auto-loaded).

# --- Proxmox Connection ---

variable "proxmox_api_url" {
  type        = string
  description = "Full URL to the Proxmox API endpoint (e.g. https://192.168.0.199:8006)"
}

variable "proxmox_api_token_id" {
  type        = string
  description = "API token ID in the format user@realm!tokenname"
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "API token secret (UUID)"
}

# --- Infrastructure ---

variable "proxmox_node" {
  type        = string
  default     = "pve"
  description = "Target Proxmox node name"
}

variable "template_id" {
  type        = number
  default     = 9000
  description = "VM ID of the Packer golden image template to clone"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key to inject via Cloud-Init (ed25519 recommended)"
}

variable "default_gateway" {
  type        = string
  default     = "10.10.20.1"
  description = "Default gateway for VMs (OPNsense KUBERNETES VLAN interface)"
}

variable "dns_server" {
  type        = string
  default     = "10.10.20.1"
  description = "DNS server for VMs (OPNsense Unbound or Pi-Hole)"
}

# --- VM Definitions ---

variable "vms" {
  type = map(object({
    vm_id    = number
    hostname = string
    cores    = number
    memory   = number
    disk     = string
    ip       = string
    tags     = list(string)
  }))
  description = "Map of VMs to provision from the golden image template"
}
