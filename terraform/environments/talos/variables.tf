# ==============================================================================
# variables.tf - Variable declarations for Talos Kubernetes cluster
# ==============================================================================

# --- Proxmox Connection ---

variable "proxmox_api_url" {
  description = "Proxmox API endpoint URL"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (format: user@realm!tokenname)"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret UUID"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

# --- Talos Image ---

variable "talos_image_id" {
  description = "Proxmox file ID for the Talos disk image (format: datastore:content_type/filename)"
  type        = string
}

# --- VM Definitions ---

variable "talos_vms" {
  description = "Map of Talos VM definitions"
  type = map(object({
    vm_id     = number
    hostname  = string
    ip        = string
    cores     = number
    memory    = number
    disk_size = number
    tags      = list(string)
  }))
}
