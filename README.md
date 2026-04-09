# Homelab — Enterprise-Grade DevSecOps Platform

[![Security Scan](https://github.com/abdelhaouari/homelab/actions/workflows/security-scan.yaml/badge.svg)](https://github.com/abdelhaouari/homelab/actions/workflows/security-scan.yaml)

Production-style home lab implementing a complete DevSecOps pipeline on bare-metal Kubernetes. Every layer — from VM provisioning to runtime threat detection — is automated, security-hardened, and deployed as code.

**If the server is destroyed, everything rebuilds from this repo.**

```
Terraform (Talos VMs)
  → talosctl (K8s bootstrap)
    → Cilium (eBPF networking + NetworkPolicies)
      → ArgoCD (GitOps, single source of truth)
        → Trivy + Checkov (shift-left scanning)
          → Cosign (image signing + SBOM)
            → Kyverno (admission control)
              → Vault (secrets injection)
                → Falco (runtime threat detection)
                  → Prometheus + Grafana + Loki (observability)

Also in this repo: Packer (Ubuntu 24.04 golden image) + Ansible (baseline hardening)
  → reusable for non-K8s VMs (monitoring, SIEM, jump hosts)
```

---

## Architecture

| Component     | Details                                            |
|---------------|----------------------------------------------------|
| Hypervisor    | Proxmox VE 9.1.6, ZFS RAIDZ-1 (~916 GB)          |
| Firewall      | OPNsense 26.1 (virtualized, router-on-a-stick)    |
| Kubernetes    | Talos Linux v1.12.6 — 4-node cluster (1 ctrl + 3 workers, K8s v1.35.2)|
| CNI           | Cilium (eBPF) replacing Flannel + kube-proxy       |
| GitOps        | ArgoCD v3.3.6 (App of Apps pattern)                |
| Monitoring    | Prometheus + Grafana + Loki                        |
| Control Plane | Windows 11 + WSL Ubuntu                           |

### Network Segmentation (VLANs via OPNsense)

| Zone        | VLAN | Subnet         | Purpose                       |
|-------------|------|----------------|-------------------------------|
| Management  | 10   | 10.10.10.0/24  | Admin access                  |
| Kubernetes  | 20   | 10.10.20.0/24  | K8s control plane and workers |
| Storage     | 30   | 10.10.30.0/24  | Persistent storage backends   |
| Lab / DMZ   | 40   | 10.10.40.0/24  | Isolated security lab         |

### Kubernetes Cluster

| Node          | IP          | Role          | OS                        |
|---------------|-------------|---------------|---------------------------|
| talos-ctrl-01 | 10.10.20.10 | Control plane | Talos Linux (immutable)   |
| talos-work-01 | 10.10.20.11 | Worker (6 GB) | Talos Linux (immutable)   |
| talos-work-02 | 10.10.20.12 | Worker (6 GB) | Talos Linux (immutable)   |
| talos-work-03 | 10.10.20.13 | Worker (6 GB) | Talos Linux (immutable)   |

### Exposed Services (MetalLB L2/ARP, FRR disabled)

| IP             | Service     | Purpose                        |
|----------------|-------------|--------------------------------|
| 10.10.20.100   | ArgoCD UI   | GitOps dashboard               |
| 10.10.20.101   | nginx-test  | Hardened test application       |
| 10.10.20.102   | Grafana     | Metrics and log dashboards     |
| 10.10.20.103   | Hubble UI   | Network flow observability     |

> IPs are dynamically assigned by MetalLB. After a rebuild, verify with `kubectl get svc -A | grep LoadBalancer`.

---

## Security Stack

This lab implements defense in depth across 6 security domains, using tools that map directly to enterprise and cloud-native security roles.

### Supply Chain Security

| Tool              | Purpose                                    | Phase |
|-------------------|--------------------------------------------|-------|
| Packer            | Reproducible, hardened golden images       | 1     |
| Trivy             | Container image CVE scanning + IaC misconfigs | 5b |
| Checkov           | IaC security scanning (CIS benchmarks)    | 5b    |
| Cosign (Sigstore) | Keyless image signing via OIDC + Fulcio/Rekor | 5c |
| SBOM (SPDX 2.3)   | Software Bill of Materials attached to images | 5c |

### Runtime Security

| Tool    | Purpose                                           | Phase |
|---------|---------------------------------------------------|-------|
| Kyverno | Kubernetes admission controller — 6 ClusterPolicies enforced | 6a |
| Vault   | Secrets injection via sidecar (Kubernetes auth, KV v2) | 6b |
| Falco   | Modern eBPF runtime threat detection (MITRE ATT&CK mapped) | 6c |
| Cilium NetworkPolicy | Pod-level ingress/egress firewall (deny-by-default) | 7b |

### Observability

| Tool             | Purpose                                    | Phase |
|------------------|--------------------------------------------|-------|
| Prometheus       | Cluster and node metrics (kube-prometheus-stack) | 7a |
| Grafana          | Dashboards and log exploration             | 7a    |
| Loki + Promtail  | Centralized log aggregation                | 7a    |
| Hubble (Cilium)  | Network flow observability (L3/L4/L7)      | 4b    |

### Security Controls Validated

The deployment was hardened iteratively using Trivy and Checkov, reducing findings from 13 to 0:

| Control | Implementation | Enforced by |
|---------|---------------|-------------|
| Non-root containers | `runAsNonRoot: true`, `runAsUser: 10001` | Kyverno (`require-run-as-nonroot`) |
| Read-only filesystem | `readOnlyRootFilesystem: true` + emptyDir mounts | securityContext |
| Drop all capabilities | `capabilities.drop: ["ALL"]` | Kyverno (`require-drop-all-capabilities`) |
| Resource limits | CPU and memory requests/limits | Kyverno (`require-resource-limits`) |
| No latest tag | Digest pinning (`image@sha256:...`) | Kyverno (`disallow-latest-tag`) |
| Image signing | Cosign keyless via Sigstore OIDC | Kyverno (`verify-image-signature`, audit) |
| Network segmentation | NetworkPolicy: egress DNS + Vault only | Cilium |
| Secrets injection | Vault Agent sidecar, app never handles secrets | Vault + Kubernetes auth |
| Runtime detection | Shell-in-container detected in real time | Falco (T1059 MITRE ATT&CK) |

---

## Attack Scenario — Defense in Depth Validated

A simulated attack was executed against the hardened nginx deployment to validate that all security layers work together:

| Attack step | Result | Control |
|------------|--------|---------|
| Deploy a non-compliant pod | **Rejected** at admission | Kyverno policies |
| Open a shell in a running container | **Detected** — Falco alert (T1059) | Falco eBPF |
| Read `/etc/shadow` | **Permission denied** — non-root user | securityContext |
| Install attacker tools (`apk add curl`) | **Permission denied** — read-only filesystem | securityContext |
| Lateral movement to ArgoCD | **Timeout** — egress blocked | NetworkPolicy |
| Exfiltrate data to internet | **Timeout** — egress blocked | NetworkPolicy |
| Access Kubernetes API | **Timeout** — egress restricted | NetworkPolicy |
| Read ServiceAccount token | Readable (required for Vault) — **no RBAC permissions** | Documented trade-off |

All alerts are centralized in Grafana via Loki for investigation.

---

## Chaos Engineering — Resilience Validated

Chaos tests were conducted to validate that the platform self-heals under real failure conditions.

### Test 1: GitOps Self-Heal

`kubectl delete namespace nginx-test` — ArgoCD detected the drift and recreated all resources (namespace, deployment, service, networkpolicy, sealedsecret, serviceaccount) in **~18 seconds**. Zero manual intervention.

### Test 2: Node Failure

A worker node was stopped (hard power-off in Proxmox) to simulate hardware failure. Kubernetes rescheduled workloads to surviving workers automatically. The test also revealed 4 latent issues — all resolved:

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Vault SPOF | Single replica, dev mode (in-memory) | Documented; HA mode for production |
| Kyverno blocking ArgoCD | Pre-existing pods lacked `resources.limits` | Added `argocd` to policy exclusions |
| MetalLB speaker crash loop | FRR/BGP enabled but unused (L2 mode) | Disabled FRR (`speaker.frr.enabled=false`) |
| Grafana crash on restart | Duplicate Loki datasource with `isDefault: true` | Disabled auto-datasource in loki-stack chart |

**Outcome**: Rebuilt cluster from scratch in ~30 minutes using the IaC runbook — 4 nodes, 59 pods, zero crashes.

### Test 3: Network Segmentation Audit (Hubble)

Hubble UI provided real-time visual proof of NetworkPolicy enforcement — forwarded flows (legitimate traffic on port 8080) and dropped flows (unauthorized access on port 9090) displayed on a live service map.

---

## Project Structure

```
homelab/
├── packer/                          # Phase 1 — Golden image builds
│   └── ubuntu-cloud/                # Ubuntu 24.04 hardened template (air-gapped autoinstall)
│
├── terraform/                       # Phase 2 & 4 — Infrastructure provisioning
│   └── environments/
│       ├── lab/                     # Ubuntu VMs (code preserved, VMs destroyed)
│       └── talos/                   # Talos Linux VMs (active, bpg/proxmox provider)
│
├── ansible/                         # Phase 3 — Configuration management
│   ├── inventory/
│   ├── roles/baseline/              # UFW, Fail2Ban, sysctl hardening, auditd
│   └── site.yml
│
├── talos/                           # Phase 4 — Cluster config (excluded from Git — PKI/secrets)
│   └── clusterconfig/
│
├── kubernetes/                      # Helm values and configs (applied manually)
│   └── monitoring/
│       ├── kube-prometheus-stack-values.yaml
│       ├── loki-stack-values.yaml
│       └── loki-datasource.yaml
│
└── gitops/                          # Phase 5+ — Everything deployed by ArgoCD
    ├── apps/                        # ArgoCD Application definitions (App of Apps)
    │   ├── nginx.yaml
    │   └── kyverno-policies.yaml
    └── manifests/                   # Kubernetes manifests (source of truth)
        ├── nginx/
        │   ├── namespace.yaml
        │   ├── deployment.yaml      # Fully hardened (see Security Controls)
        │   ├── service.yaml
        │   ├── serviceaccount.yaml
        │   ├── sealedsecret.yaml
        │   └── networkpolicy.yaml
        └── kyverno-policies/
            ├── disallow-latest-tag.yaml
            ├── require-run-as-nonroot.yaml
            ├── require-resource-limits.yaml
            ├── require-drop-all-capabilities.yaml
            ├── require-labels.yaml
            └── verify-image-signature.yaml
```

---

## Phases

- [x] **Phase 0** — Proxmox foundations, ZFS, VLAN segmentation, OPNsense firewall
- [x] **Phase 1** — Golden image with Packer (Ubuntu 24.04, air-gapped autoinstall, OS hardening)
- [x] **Phase 2** — Infrastructure as Code with Terraform (bpg/proxmox, Cloud-Init, `for_each`)
- [x] **Phase 3** — Configuration management with Ansible (UFW, Fail2Ban, sysctl, auditd)
- [x] **Phase 4** — Kubernetes with Talos Linux (immutable OS, mTLS, API-only, 4 nodes, etcd encryption)
- [x] **Phase 4b** — Cilium (eBPF CNI, kube-proxy replacement), Hubble, MetalLB (L2/ARP)
- [x] **Phase 5a** — GitOps: ArgoCD (App of Apps, self-heal), Sealed Secrets
- [x] **Phase 5b** — Shift-left security: Trivy (CVE + misconfig), Checkov (CIS benchmarks)
- [x] **Phase 5c** — Supply chain: Cosign keyless signing (Sigstore/Fulcio/Rekor), SBOM (SPDX 2.3)
- [x] **Phase 6a** — Policy enforcement: Kyverno (6 ClusterPolicies, 5 Enforce + 1 Audit)
- [x] **Phase 6b** — Secrets management: HashiCorp Vault (KV v2, Kubernetes auth, sidecar injection)
- [x] **Phase 6c** — Runtime security: Falco (modern eBPF, MITRE ATT&CK mapped, Falcosidekick)
- [x] **Phase 7a** — Observability: Prometheus + Grafana (20+ dashboards), Loki + Promtail
- [x] **Phase 7b** — Network segmentation: Cilium NetworkPolicies + attack scenario validation
- [x] **Phase J2-1** — Chaos engineering: self-heal, node failure resilience, Hubble network audit

---

## Quick Start

### Prerequisites

Proxmox VE 8+ with ZFS, OPNsense for VLAN routing, and a Linux workstation (or WSL) with:

`packer` · `terraform` · `ansible` · `talosctl` · `kubectl` · `helm` · `cilium-cli` · `argocd` · `kubeseal` · `trivy` · `checkov` · `cosign` · `vault`

### Rebuild the Kubernetes Platform

```bash
# 1. Provision Talos VMs
cd terraform/environments/talos
terraform apply

# 2. Bootstrap Kubernetes
talosctl gen config homelab-k8s https://10.10.20.10:6443 \
  --config-patch-control-plane @patches/cni-proxy.yaml
talosctl apply-config --insecure -n <NODE_IP> --file <config>.yaml
talosctl bootstrap --endpoints 10.10.20.10 --nodes 10.10.20.10

# 3. Install networking
helm install cilium cilium/cilium --namespace kube-system [...]
helm install metallb metallb/metallb --namespace metallb-system --create-namespace \
  --set speaker.frr.enabled=false

# 4. Install GitOps (ArgoCD syncs everything else from Git)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  --server-side --force-conflicts
argocd app create root --repo https://github.com/abdelhaouari/homelab.git \
  --path gitops/apps --sync-policy automated --auto-prune --self-heal

# 5. Install security stack
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace
helm install vault hashicorp/vault --namespace vault --create-namespace \
  --set server.dev.enabled=true --set injector.enabled=true
helm install falco falcosecurity/falco --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=false

# 6. Install observability
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --values kubernetes/monitoring/kube-prometheus-stack-values.yaml
helm install loki-stack grafana/loki-stack \
  --namespace monitoring --values kubernetes/monitoring/loki-stack-values.yaml
# Important: loki-stack-values.yaml must set grafana.sidecar.datasources.enabled=false
# to avoid duplicate default datasource conflict with Prometheus
```

### Build Ubuntu Golden Image (for non-K8s VMs)

Packer builds a hardened Ubuntu 24.04 template for traditional VMs (monitoring, SIEM, jump hosts). Not used for Talos — Talos ships its own immutable image.

```bash
cd packer/ubuntu-cloud
packer build -var-file=credentials.pkrvars.hcl .
# Produces Proxmox template ID 9000 (~8 min build time)
```

---

## GitOps Workflow

All application deployments flow through Git:

```
Developer commits to main
  → ArgoCD detects change (polling or webhook)
    → Manifests are applied to the cluster
      → Kyverno validates at admission (blocks non-compliant resources)
        → Vault Agent injects secrets into pods
          → Falco monitors runtime behavior
            → Prometheus scrapes metrics, Promtail collects logs
              → Grafana displays dashboards and alerts
```

To deploy a new application:
1. Add Kubernetes manifests to `gitops/manifests/<app>/`
2. Add an ArgoCD Application definition to `gitops/apps/<app>.yaml`
3. `git commit && git push` — ArgoCD handles the rest

Manual changes to the cluster are automatically reverted by ArgoCD's self-heal.

---

## Security Principles

| Principle | Implementation |
|-----------|---------------|
| Least privilege | Per-tool API tokens, PodSecurity labels per namespace, RBAC scoped to namespace |
| Immutable infrastructure | Packer golden images, Talos Linux (no SSH, no shell, API-only) |
| Secrets management | Sealed Secrets for Git, Vault sidecar injection at runtime, `.gitignore` for local secrets |
| Network segmentation | VLANs (OPNsense), Cilium NetworkPolicies (deny-by-default egress) |
| Defense in depth | Perimeter FW → VLAN isolation → PodSecurity → Kyverno admission → NetworkPolicy → Falco runtime |
| Shift-left security | Trivy + Checkov scan manifests and images before deployment |
| Supply chain security | Cosign keyless signing, SBOM generation, digest pinning (no mutable tags) |
| GitOps | Git is the single source of truth; drift is auto-corrected |
| Audit trail | Git commit history, Kubernetes audit logs, Falco alerts in Loki/Grafana |
| Reproducibility | Full destroy and rebuild from code |

---

## Tools

| Tool | Category | Status |
|------|----------|--------|
| Proxmox VE | Hypervisor | Deployed |
| OPNsense | Firewall / Router | Deployed |
| Packer | Image builds | Deployed |
| Terraform (bpg/proxmox) | Infrastructure provisioning | Deployed |
| Ansible | Configuration management | Deployed |
| Talos Linux | Immutable Kubernetes OS | Deployed |
| Cilium + Hubble | eBPF CNI / Network observability | Deployed |
| MetalLB | Bare-metal load balancer (L2/ARP, FRR disabled) | Deployed |
| ArgoCD | GitOps continuous delivery | Deployed |
| Sealed Secrets | Encrypted secrets in Git | Deployed |
| Trivy | CVE + IaC scanner | Deployed |
| Checkov | IaC security scanner (CIS) | Deployed |
| Cosign (Sigstore) | Image signing + verification | Deployed |
| Kyverno | Policy enforcement (admission) | Deployed |
| HashiCorp Vault | Secrets management | Deployed |
| Falco | Runtime threat detection (modern eBPF) | Deployed |
| Prometheus + Grafana | Metrics + dashboards | Deployed |
| Loki + Promtail | Log aggregation | Deployed |
