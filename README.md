# Homelab - Enterprise-Grade Infrastructure as Code

Production-style home lab built with security-first principles, fully automated with Infrastructure as Code. Designed as a hands-on training environment for Cloud Security, DevSecOps, and Kubernetes.

## Architecture

| Component     | Details                                           |
|---------------|---------------------------------------------------|
| Hypervisor    | Proxmox VE 9.1.6                                 |
| Storage       | ZFS RAIDZ-1 (3x Samsung, ~916 GB usable)         |
| Firewall      | OPNsense 26.1 (virtualized, router-on-a-stick)   |
| Kubernetes    | Talos Linux v1.12.6 — 3-node cluster (K8s v1.35.2) |
| GitOps        | ArgoCD v3.3.6 — declarative deployments from Git |
| Control Plane | Windows 11 + WSL Ubuntu                          |

### Network Segmentation

| Zone          | VLAN | Subnet         | Purpose                        |
|---------------|------|----------------|--------------------------------|
| Management    | 10   | 10.10.10.0/24  | Admin access, monitoring       |
| Kubernetes    | 20   | 10.10.20.0/24  | K8s control plane and workers  |
| Storage       | 30   | 10.10.30.0/24  | Persistent storage backends    |
| Lab / DMZ     | 40   | 10.10.40.0/24  | Isolated security lab          |

### Kubernetes Cluster (VLAN 20)

| Node          | VM ID | IP             | Role          | OS          |
|---------------|-------|----------------|---------------|-------------|
| talos-ctrl-01 | 201   | 10.10.20.10    | Control plane | Talos Linux |
| talos-work-01 | 202   | 10.10.20.11    | Worker        | Talos Linux |
| talos-work-02 | 203   | 10.10.20.12    | Worker        | Talos Linux |

### Cluster Services

| Service              | IP / Access        | Purpose                              |
|----------------------|--------------------|--------------------------------------|
| Hubble UI            | 10.10.20.100       | Network observability (Cilium)       |
| ArgoCD UI            | 10.10.20.101       | GitOps dashboard                     |
| K8s API              | 10.10.20.10:6443   | Kubernetes API server                |

## Project Structure

```
homelab/
├── packer/                  # Phase 1 — Golden image builds
│   └── ubuntu-cloud/        # Ubuntu 24.04 hardened template
├── terraform/               # Phase 2 & 4 — Infrastructure provisioning
│   └── environments/
│       ├── lab/             # Ubuntu VMs (code preserved, VMs destroyed)
│       └── talos/           # Talos Linux VMs (active)
├── ansible/                 # Phase 3 — Configuration management
│   ├── inventory/           # Host inventory (YAML)
│   ├── roles/
│   │   └── baseline/        # Security hardening role
│   └── site.yml             # Main playbook
├── talos/                   # Phase 4 — Cluster config (excluded from Git)
│   └── clusterconfig/       # Machine configs, PKI, kubeconfig
├── gitops/                  # Phase 5a — GitOps deployments
│   ├── apps/                # ArgoCD Application definitions (App of Apps)
│   └── manifests/           # Kubernetes manifests deployed by ArgoCD
│       └── nginx/           # Test app with SealedSecret
└── docs/                    # Architecture diagrams and decisions
```

## Phases

- [x] **Phase 0** — Proxmox foundations, ZFS, network segmentation, OPNsense
- [x] **Phase 1** — Golden image with Packer (Ubuntu 24.04, autoinstall, air-gapped)
- [x] **Phase 2** — Infrastructure as Code with Terraform (bpg/proxmox, Cloud-Init, `for_each`)
- [x] **Phase 3** — Configuration management with Ansible (baseline security hardening)
- [x] **Phase 4** — Kubernetes cluster with Talos Linux (immutable OS, API-only, mTLS)
- [x] **Phase 4b** — Kubernetes networking: Cilium (eBPF CNI), Hubble, MetalLB (L2/ARP)
- [x] **Phase 5a** — GitOps core: ArgoCD (App of Apps), Sealed Secrets (encrypted secrets in Git)
- [ ] **Phase 5b** — Pipeline security: Trivy, Checkov (shift-left scanning)
- [ ] **Phase 5c** — Supply chain security: Cosign (image signing), SBOM generation
- [ ] **Phase 6** — Policy enforcement (Kyverno), secrets management (Vault), runtime security (Falco)
- [ ] **Phase 7** — Observability (Prometheus, Grafana, Loki) & offensive security lab

## IaC Pipeline

The full infrastructure lifecycle is automated and reproducible:

```
Packer (golden image) → Terraform (VMs) → Talos (K8s bootstrap) → ArgoCD (GitOps)
```

If the server is destroyed, everything can be rebuilt from code:

```bash
# Phase 1 — Build the golden image template
cd packer/ubuntu-cloud && packer build -var-file=credentials.pkrvars.hcl .

# Phase 4 — Provision Talos VMs
cd terraform/environments/talos && terraform apply

# Phase 4 — Bootstrap Kubernetes (talosctl gen config → apply-config → bootstrap)
# Phase 4b — Install Cilium, MetalLB (Helm)
# Phase 5a — Install ArgoCD, Sealed Secrets, create root app
#            → ArgoCD syncs all applications from gitops/ automatically
```

## Security Principles

Every phase follows these DevSecOps principles:

- **Least privilege** — Dedicated API tokens per tool, PodSecurity labels per namespace, no shared credentials
- **Secrets management** — Sensitive values excluded from Git via `.gitignore`; Kubernetes secrets encrypted with Sealed Secrets for safe Git storage; `.example` templates provided for credentials
- **Network segmentation** — VLAN isolation with firewall rules between zones; Cilium eBPF for in-cluster network policies
- **Defense in depth** — Perimeter firewall (OPNsense) + host firewall (UFW) + kernel hardening (sysctl) + immutable OS (Talos) + mTLS on all cluster communications
- **Immutable infrastructure** — Golden images built by Packer; Talos Linux has no SSH, no shell, API-only management
- **GitOps** — Git is the single source of truth; ArgoCD continuously reconciles cluster state; drift is auto-corrected via self-heal
- **Configuration as Code** — No manual changes; Ansible enforces desired state on traditional VMs; ArgoCD enforces desired state on Kubernetes
- **Audit trail** — System-level auditing (auditd) on managed hosts; Git commit history as deployment audit trail via ArgoCD
- **Reproducibility** — Destroy and rebuild everything from code in under 20 minutes

## Getting Started

### Prerequisites

- Proxmox VE 8+ with ZFS storage
- OPNsense (virtualized or physical) for network segmentation
- WSL Ubuntu or Linux workstation with: Packer, Terraform, Ansible, talosctl, kubectl, Helm, Cilium CLI, ArgoCD CLI, kubeseal

### Phase 1 — Packer (Golden Image)

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
- Autoinstall delivered via mounted ISO (air-gapped — no HTTP dependency from WSL).

### Phase 2 — Terraform (Ubuntu VM Provisioning)

> **Note:** These Ubuntu VMs have been replaced by Talos Linux VMs in Phase 4. The Terraform code is preserved for reference.

```bash
cd terraform/environments/lab
cp credentials.auto.tfvars.example credentials.auto.tfvars
# Edit credentials.auto.tfvars with your Proxmox API token and SSH public key
terraform init
terraform plan
terraform apply
```

| VM | Hostname | IP | Role |
|----|----------|----|------|
| 201 | k8s-ctrl-01 | 10.10.20.10 | Kubernetes control plane |
| 202 | k8s-work-01 | 10.10.20.11 | Kubernetes worker node |
| 203 | k8s-work-02 | 10.10.20.12 | Kubernetes worker node |

### Phase 3 — Ansible (Configuration Management)

```bash
cd ansible
ansible-playbook site.yml
```

Applies the `baseline` security hardening role to all managed hosts. See [`ansible/README.md`](ansible/README.md) for details on the role and its configuration.

### Phase 4 — Talos Linux (Kubernetes Cluster)

Talos Linux is an immutable, API-only OS purpose-built for Kubernetes. No SSH, no shell — all management through `talosctl` with mTLS authentication.

```bash
cd terraform/environments/talos
cp credentials.auto.tfvars.example credentials.auto.tfvars
# Edit credentials.auto.tfvars with your Proxmox API token
terraform init
terraform apply
```

After VMs are provisioned, bootstrap the cluster:

```bash
# Generate cluster config (with CNI and kube-proxy disabled for Cilium)
talosctl gen config homelab-k8s https://10.10.20.10:6443 \
  --output-dir ~/homelab/talos/clusterconfig \
  --install-disk /dev/sda \
  --config-patch-control-plane @patches/cni-proxy.yaml

# Apply configs to each node, bootstrap, get kubeconfig
talosctl apply-config --insecure -n <NODE_IP> --file <config>.yaml --config-patch @patches/<node>.yaml
talosctl bootstrap --endpoints 10.10.20.10 --nodes 10.10.20.10
talosctl kubeconfig ~/homelab/talos/clusterconfig/kubeconfig
```

> **Security by default:** mTLS on all communications, Seccomp on all containers, PodSecurity `baseline` enforced, etcd encryption at rest, audit policy enabled.

### Phase 4b — Cilium & MetalLB

Cilium replaces both Flannel (CNI) and kube-proxy with eBPF-based networking. MetalLB provides LoadBalancer IPs for bare-metal.

```bash
# Install Cilium with Talos-specific settings
helm install cilium cilium/cilium --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost --set k8sServicePort=7445 \
  --set hubble.enabled=true --set hubble.relay.enabled=true --set hubble.ui.enabled=true
  # (additional Talos-specific capabilities and cgroup settings required — see docs/)

# Install MetalLB
helm install metallb metallb/metallb --namespace metallb-system --create-namespace
# Configure IP pool: 10.10.20.100-150
```

### Phase 5a — ArgoCD & Sealed Secrets (GitOps)

ArgoCD watches the `gitops/` directory and continuously deploys applications to the cluster. Sealed Secrets enables encrypted credentials in a public Git repo.

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Install Sealed Secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system --set fullnameOverride=sealed-secrets-controller

# Create the root application (App of Apps pattern)
argocd app create root \
  --dest-server https://kubernetes.default.svc --dest-namespace argocd \
  --repo https://github.com/abdelhaouari/homelab.git --path gitops/apps \
  --sync-policy automated --auto-prune --self-heal
```

**GitOps workflow:** To deploy or update an application, commit Kubernetes manifests to `gitops/manifests/<app>/` and an ArgoCD Application definition to `gitops/apps/`. ArgoCD detects the change and reconciles the cluster automatically.

**Sealing a secret:**

```bash
kubectl create secret generic my-secret --from-literal=KEY=value --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets-controller --controller-namespace=kube-system --format yaml \
  > gitops/manifests/<app>/sealedsecret.yaml
```

The resulting `SealedSecret` is safe to commit to a public repo — only the controller inside the cluster can decrypt it.
