# Terraform — Infrastructure Provisioning

Phase 2: Declarative VM provisioning from Packer golden image templates using the bpg/proxmox provider.

## Architecture

All VMs are full clones of the Packer-built Ubuntu 24.04 template (ID 9000). Cloud-Init injects static IPs, SSH keys, and hostnames at first boot.

| VM | ID | Hostname | IP | Role |
|----|----|----------|-----|------|
| Control Plane | 101 | k8s-ctrl-01 | 10.10.20.10 | Kubernetes control plane |
| Worker 1 | 102 | k8s-work-01 | 10.10.20.11 | Kubernetes worker node |
| Worker 2 | 103 | k8s-work-02 | 10.10.20.12 | Kubernetes worker node |

## File Structure

| File | Purpose | Git tracked? |
|------|---------|--------------|
| `provider.tf` | Provider and Terraform version constraints | Yes |
| `variables.tf` | Variable declarations with types and descriptions | Yes |
| `main.tf` | VM resources (clone, Cloud-Init, network) | Yes |
| `outputs.tf` | Post-deploy info (IPs, SSH commands) | Yes |
| `terraform.auto.tfvars` | Non-sensitive values (auto-loaded) | Yes |
| `credentials.auto.tfvars` | Secrets: API token, SSH key (auto-loaded) | **No** |
| `credentials.auto.tfvars.example` | Template for required secrets | Yes |

## Usage

```bash
cd terraform/environments/lab
cp credentials.auto.tfvars.example credentials.auto.tfvars
# Edit credentials.auto.tfvars with your Proxmox API token and SSH public key
terraform init
terraform plan
terraform apply
```

## Security Notes

- **State file** (`terraform.tfstate`) contains sensitive data and is excluded from Git
- **API token** uses the same `admin@pve!packer` token with least-privilege access
- **SSH keys** are injected via Cloud-Init — password authentication is disabled in the template
- **Cloud-Init handoff**: Packer builds the image, Terraform configures the instance
