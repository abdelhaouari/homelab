# Homelab - Enterprise-Grade Infrastructure as Code

Production-style home lab built with security-first principles, fully automated with Infrastructure as Code. Designed as a hands-on training environment for Cloud Security, DevSecOps, and Kubernetes.

## Architecture

| Component     | Details                                           |
|---------------|---------------------------------------------------|
| Hypervisor    | Proxmox VE 9.1.6                                 |
| Storage       | ZFS RAIDZ-1 (3x Samsung, ~916 GB usable)         |
| Firewall      | OPNsense 26.1 (virtualized, router-on-a-stick)   |
| Control Plane | Windows 11 + WSL Ubuntu                          |

### Network Segmentation

| Zone          | VLAN | Subnet         | Purpose                        |
|---------------|------|----------------|--------------------------------|
| Management    | 10   | 10.10.10.0/24  | Admin access, monitoring       |
| Kubernetes    | 20   | 10.10.20.0/24  | K8s control plane and workers  |
| Storage       | 30   | 10.10.30.0/24  | Persistent storage backends    |
| Lab / DMZ     | 40   | 10.10.40.0/24  | Isolated security lab          |

## Project Structure

```
homelab/
├── packer/              # Phase 1 - Golden image builds
│   └── ubuntu-cloud/    # Ubuntu 24.04 hardened template
├── terraform/           # Phase 2 - Infrastructure provisioning
├── ansible/             # Phase 3 - Configuration management
├── kubernetes/          # Phase 4 - Cluster deployment (Talos)
├── gitops/              # Phase 5 - Flux CD / ArgoCD
└── docs/                # Architecture diagrams and decisions
```

## Phases

- [x] **Phase 0** - Proxmox foundations, ZFS, network segmentation, OPNsense
- [x] **Phase 1** - Golden image with Packer (Ubuntu 24.04, autoinstall, air-gapped)
- [ ] **Phase 2** - Infrastructure as Code with Terraform/OpenTofu
- [ ] **Phase 3** - Configuration management with Ansible
- [ ] **Phase 4** - Kubernetes cluster (Talos Linux)
- [ ] **Phase 5** - GitOps & continuous deployment
- [ ] **Phase 6** - Observability, monitoring & security lab

## Security Principles

Every phase follows these DevSecOps principles:

- **Least privilege** - Dedicated API tokens per tool, no shared credentials
- **Secrets management** - Sensitive values excluded from Git, `.example` templates provided
- **Network segmentation** - VLAN isolation with firewall rules between zones
- **Immutable infrastructure** - Golden images built by code, not configured by hand
- **Reproducibility** - Destroy and rebuild everything from code

## Getting Started

### Prerequisites

- Proxmox VE 8+ with ZFS storage
- OPNsense (virtualized or physical) for network segmentation
- WSL Ubuntu or Linux workstation with: Packer, Terraform, Ansible

### Packer (Golden Image)

The Packer configuration uses a split-file structure following HashiCorp conventions:

| File | Purpose | Git tracked? |
|------|---------|--------------|
| `ubuntu-cloud.pkr.hcl` | Build definition (source, provisioners, build blocks) | Yes |
| `variables.pkr.hcl` | Variable declarations with types and descriptions | Yes |
| `ubuntu-cloud.auto.pkrvars.hcl` | Non-sensitive default values (auto-loaded by Packer) | Yes |
| `credentials.pkrvars.hcl` | Secrets: API tokens, passwords (manually loaded) | **No** |
| `credentials.pkrvars.hcl.example` | Template showing required secret variables | Yes |
| `http/user-data` | Ubuntu autoinstall configuration | Yes |
| `http/meta-data` | Cloud-init metadata (required, can be empty) | Yes |

Packer automatically loads all `*.pkr.hcl` and `*.auto.pkrvars.hcl` files in the directory. Only the secrets file needs to be passed explicitly with `-var-file`.

```bash
cd packer/ubuntu-cloud
cp credentials.pkrvars.hcl.example credentials.pkrvars.hcl
# Edit credentials.pkrvars.hcl with your Proxmox API token and build password
packer init .
packer validate -var-file=credentials.pkrvars.hcl .
packer build -var-file=credentials.pkrvars.hcl .
```

The build takes ~8 minutes and produces a Proxmox template (VM ID 9000) with:

- Ubuntu 24.04 LTS with LVM partitioning
- QEMU Guest Agent enabled
- Cloud-Init ready for Terraform deployment
- **Ephemeral Privilege Management:** Uses Cloud-Init to create temporary `NOPASSWD` sudo scaffolding for automation, which is strictly destroyed via a shell provisioner before template sealing.
- **Aggressive OS Hardening:** SSH password auth disabled, build password locked, bash history purged, and machine-id cleared to prevent IP conflicts across clones.
- Autoinstall delivered via mounted ISO (air-gapped - no HTTP dependency from WSL).
