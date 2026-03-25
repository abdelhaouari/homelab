# ==============================================================================
# provider.tf - Proxmox provider configuration for Talos Kubernetes cluster
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent    = false
    username = "root"
    node {
      name    = "pve"
      address = "192.168.0.199"
      port    = 2222
    }
    private_key = file("~/.ssh/id_ed25519")
  }
}
