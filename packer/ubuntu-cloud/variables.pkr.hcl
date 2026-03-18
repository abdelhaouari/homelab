# ============================================================
# variables.pkr.hcl — Variable declarations for Ubuntu Golden Image
# ============================================================
# This file declares all variables used by the Packer build.
# Sensitive values are loaded from credentials.pkrvars.hcl (excluded from Git).
# Non-sensitive defaults are in ubuntu-cloud.auto.pkrvars.hcl.

# --- Proxmox Connection ---

variable "proxmox_api_url" {
  type        = string
  description = "Full URL to the Proxmox API endpoint"
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

# --- VM Configuration ---

variable "vm_id" {
  type        = number
  default     = 9000
  description = "Proxmox VM ID for the Packer build VM and resulting template"
}

variable "vm_name" {
  type        = string
  default     = "ubuntu-2404-golden-image"
  description = "Name of the temporary VM during build"
}

variable "template_name" {
  type        = string
  default     = "ubuntu-2404-golden"
  description = "Name of the resulting Proxmox template"
}

variable "proxmox_node" {
  type        = string
  default     = "pve"
  description = "Target Proxmox node for the build"
}

# --- Network ---

variable "network_bridge" {
  type        = string
  default     = "vmbr1"
  description = "Proxmox bridge for the VM network adapter"
}

variable "vlan_tag" {
  type        = number
  default     = 20
  description = "VLAN tag for network segmentation"
}

# --- SSH (Temporary Build Credentials) ---

variable "ssh_username" {
  type        = string
  default     = "labadmin"
  description = "Username for SSH connection during build (must match autoinstall identity)"
}

variable "ssh_password" {
  type        = string
  sensitive   = true
  description = "Temporary password for SSH during build (only used by Packer, not in final template)"
}
