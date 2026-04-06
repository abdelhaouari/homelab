# Terraform — Infrastructure Provisioning

This directory contains Terraform configurations for provisioning VMs on Proxmox VE using the [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox) provider.

## Environments

### `environments/talos/` — Talos Linux VMs (Active)

Provisions 3 VMs for the Kubernetes cluster running Talos Linux, an immutable, API-only OS.

| Resource        | VM ID | Hostname      | IP           | Role          | Cores | RAM    |
|-----------------|-------|---------------|--------------|---------------|-------|--------|
| `talos_vm[ctrl]`| 201   | talos-ctrl-01 | 10.10.20.10  | Control plane | 2     | 4096 MB|
| `talos_vm[w1]`  | 202   | talos-work-01 | 10.10.20.11  | Worker        | 2     | 4096 MB|
| `talos_vm[w2]`  | 203   | talos-work-02 | 10.10.20.12  | Worker        | 2     | 4096 MB|

**Key design decisions:**
- `for_each` on a map (not `count`) — allows adding/removing nodes without index shifting
- `file_id` imports the Talos disk image directly (no Cloud-Init, no clone)
- `stop_on_destroy = true` — Talos has no QEMU Guest Agent, graceful shutdown isn't possible
- SSH block in the provider is required for `file_id` to upload the disk image to Proxmox

### `environments/lab/` — Ubuntu VMs (Code Preserved, VMs Destroyed)

Original Phase 2 configuration that clones from the Packer golden image (template ID 9000). Uses Cloud-Init for IP assignment and SSH key injection. VMs were destroyed when replaced by Talos in Phase 4.

The code is preserved as a reusable template for future non-Kubernetes VMs.

## File Structure

```
terraform/
├── README.md
├── modules/                          # Shared modules (future use)
│   └── .gitkeep
└── environments/
    ├── lab/                          # Ubuntu VMs (Phase 2)
    │   ├── provider.tf               # bpg/proxmox ~0.78
    │   ├── variables.tf
    │   ├── main.tf                   # for_each, clone, Cloud-Init
    │   ├── outputs.tf
    │   ├── terraform.auto.tfvars     # Non-sensitive values
    │   └── credentials.auto.tfvars.example
    └── talos/                        # Talos VMs (Phase 4 — ACTIVE)
        ├── .terraform.lock.hcl       # Provider lock file
        ├── provider.tf               # bpg/proxmox ~0.78 + ssh {}
        ├── variables.tf
        ├── main.tf                   # for_each, disk file_id import
        ├── outputs.tf
        ├── terraform.auto.tfvars     # VM map (non-sensitive)
        └── credentials.auto.tfvars.example
```

## Usage

```bash
cd environments/talos

# First time — copy and fill in credentials
cp credentials.auto.tfvars.example credentials.auto.tfvars
# Edit: proxmox_api_token_id, proxmox_api_token_secret

terraform init
terraform plan
terraform apply
```

## Credentials

Sensitive values are stored in `credentials.auto.tfvars` (excluded from Git via `.gitignore`). The `.example` file shows the required variables:

```hcl
proxmox_api_token_id     = "admin@pve!packer"
proxmox_api_token_secret = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

The provider uses a single `api_token` string in the format `"user@realm!token=secret-uuid"`, constructed from these two variables.

## Provider Configuration

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
  }
}
```

The Talos environment also requires an SSH connection to Proxmox for the `file_id` disk import:

```hcl
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent    = false
    username = "root"
    port     = 2222
    private_key = file("~/.ssh/id_ed25519")
  }
}
```

## Key Differences: Ubuntu vs Talos

| Aspect           | Ubuntu (`lab/`)                  | Talos (`talos/`)                    |
|------------------|----------------------------------|-------------------------------------|
| Source           | `clone {}` from template 9000   | `disk { file_id }` raw image import|
| Configuration    | Cloud-Init (`initialization {}`) | Talos API (`talosctl apply-config`) |
| QEMU Agent       | Enabled                          | Disabled (Talos has no agent)       |
| Shutdown         | Graceful via agent               | `stop_on_destroy = true`            |
| SSH in provider  | Not needed                       | Required for `file_id` upload       |

## Important Notes

- **No `local-lvm`** — this Proxmox uses ZFS. Disk `datastore_id` must be `local-zfs`
- **State files are local** and excluded from Git (`.gitignore` covers `*.tfstate*` and `.terraform/`)
- **`for_each` over `count`** — preferred for VM maps to avoid index-based recreation on changes
