# ============================================================
# ubuntu-cloud.auto.pkrvars.hcl — Non-sensitive default values
# ============================================================
# This file is auto-loaded by Packer (no -var-file flag needed).
# It contains ONLY non-sensitive, environment-specific values.
# Secrets go in credentials.pkrvars.hcl (excluded from Git).

vm_id          = 9000
vm_name        = "ubuntu-2404-golden-image"
template_name  = "ubuntu-2404-golden"
proxmox_node   = "pve"
network_bridge = "vmbr1"
vlan_tag       = 20
ssh_username   = "labadmin"
