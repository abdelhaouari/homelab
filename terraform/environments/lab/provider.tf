# ============================================================
# provider.tf — Proxmox Provider Configuration
# ============================================================
# Uses the bpg/proxmox provider (most actively maintained).
# Authentication via API token (least privilege — no password needed).

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

  # Accept self-signed certificate (home lab)
  insecure = true

  ssh {
    agent = false
  }
}
