# Architecture Decisions & Documentation

This directory contains architecture diagrams, network topology, and design decisions for the homelab.

## Network Topology

See the main README for VLAN segmentation details.

## Design Decisions

### Phase 0 — Foundations
- **PVE realm over PAM** for Proxmox users (no Linux shell exposure)
- **Ed25519 SSH keys** with password auth disabled on Proxmox host
- **Router-on-a-stick** with OPNsense for inter-VLAN routing
- **Checksum offload disabled** on OPNsense (VirtIO has no hardware offload)
- **"Disable reply-to"** on OPNsense to fix asymmetric routing with private WAN

### Phase 1 — Packer
- **Air-gapped autoinstall** via mounted ISO instead of HTTP (WSL2 NAT isolation)
- **QEMU Guest Agent** required for Packer SSH discovery via Proxmox API
- **Cloud-Init enabled** on template for Terraform/Ansible post-deploy configuration
