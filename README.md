# Homelab — Enterprise-Grade DevSecOps Platform

[![Security Scan](https://github.com/abdelhaouari/homelab/actions/workflows/security-scan.yaml/badge.svg)](https://github.com/abdelhaouari/homelab/actions/workflows/security-scan.yaml)

Production-style home lab implementing a complete DevSecOps pipeline on bare-metal Kubernetes. Every layer — from VM provisioning to runtime threat detection — is automated, security-hardened, and deployed as code.

**If the server is destroyed, everything rebuilds from this repo.**

```
Terraform (Talos VMs)
  → talosctl (K8s bootstrap)
    → Cilium (eBPF networking + Gateway API + NetworkPolicies)
      → ArgoCD (GitOps, single source of truth)
        → Trivy + Checkov (shift-left scanning)
          → Cosign (image signing + SBOM)
            → Kyverno (admission control + mutate policies)
              → Vault (secrets injection)
                → Falco (runtime threat detection)
                  → cert-manager + Let's Encrypt (automated TLS)
                    → Prometheus + Grafana + Loki (observability)

Also in this repo: Packer (Ubuntu 24.04 golden image) + Ansible (baseline hardening)
  → reusable for non-K8s VMs (monitoring, SIEM, jump hosts)
```

---

## Architecture

| Component     | Details                                            |
|---------------|---------------------------------------------------|
| Hypervisor    | Proxmox VE 9.1.6, ZFS RAIDZ-1 (~916 GB)          |
| Firewall      | OPNsense 26.1 (virtualized, router-on-a-stick)    |
| Kubernetes    | Talos Linux v1.12.6 — 4-node cluster (1 ctrl + 3 workers, K8s v1.35.2) |
| CNI           | Cilium (eBPF) replacing Flannel + kube-proxy       |
| Ingress       | Cilium Gateway API (L7 routing, single entry point) |
| TLS           | cert-manager with Let's Encrypt (DNS-01) + private CA |
| GitOps        | ArgoCD v3.3.6 (App of Apps pattern)                |
| Monitoring    | Prometheus + Grafana + Loki                        |
| VPN           | WireGuard (built-in OPNsense 26) + Cloudflare DDNS |
| Domain        | `ahaouari.com` (Cloudflare, DNS-01 challenges)    |
| Control Plane | Windows 11 + WSL Ubuntu                           |

### Network Segmentation (VLANs via OPNsense)

| Zone        | VLAN | Subnet         | Purpose                       |
|-------------|------|----------------|-------------------------------|
| Management  | 10   | 10.10.10.0/24  | Admin access                  |
| Kubernetes  | 20   | 10.10.20.0/24  | K8s control plane and workers |
| Storage     | 30   | 10.10.30.0/24  | Persistent storage backends   |
| Lab / DMZ   | 40   | 10.10.40.0/24  | Isolated security lab         |
| WireGuard   | —    | 10.10.50.0/24  | Remote VPN access (tunnel, not a VLAN) |

### Kubernetes Cluster

| Node          | IP          | Role          | OS                        |
|---------------|-------------|---------------|---------------------------|
| talos-ctrl-01 | 10.10.20.10 | Control plane | Talos Linux (immutable)   |
| talos-work-01 | 10.10.20.11 | Worker (6 GB) | Talos Linux (immutable)   |
| talos-work-02 | 10.10.20.12 | Worker (6 GB) | Talos Linux (immutable)   |
| talos-work-03 | 10.10.20.13 | Worker (6 GB) | Talos Linux (immutable)   |

### Exposed Services (MetalLB L2/ARP + Cilium Gateway API)

| IP             | Service         | Access method                          |
|----------------|-----------------|----------------------------------------|
| 10.10.20.100   | ArgoCD UI       | Direct LoadBalancer (stability)        |
| 10.10.20.103   | Cilium Gateway  | Single L7 entry point for all HTTPRoutes |
| 10.10.20.105   | Harbor          | Direct LoadBalancer (pinned annotation) |

Services behind the Cilium Gateway are accessed by hostname, with TLS terminated by Envoy:

| Hostname                  | Backend          | TLS certificate       |
|---------------------------|------------------|-----------------------|
| `nginx.homelab.local`     | nginx-test       | Private CA (cert-manager) |
| `grafana.homelab.local`   | Grafana          | Private CA (cert-manager) |
| `hubble.homelab.local`    | Hubble UI        | Private CA (cert-manager) |
| `podinfo.homelab.local`   | Podinfo          | Private CA (cert-manager) |
| `rexpn.ahaouari.com`      | REXPN            | Let's Encrypt (public) |

> All `*.homelab.local` hostnames resolve to internal IPs via OPNsense Unbound DNS overrides (split-horizon). These services are not exposed to the internet — accessible only from the local network or via WireGuard VPN. HTTP requests are automatically redirected to HTTPS (301).

> MetalLB IPs are dynamically assigned (except Harbor, pinned via annotation). After a rebuild, verify with `kubectl get svc -A | grep LoadBalancer`.

---

## Security Stack

This lab implements defense in depth across 6 security domains, using tools that map directly to enterprise and cloud-native security roles.

### Supply Chain Security

| Tool              | Purpose                                    | Phase |
|-------------------|--------------------------------------------|-------|
| Packer            | Reproducible, hardened golden images       | 1     |
| Trivy             | Container image CVE scanning + IaC misconfigs | 5b |
| Checkov           | IaC security scanning (CIS benchmarks)    | 5b    |
| Cosign (Sigstore) | Key-based image signing, verified at admission | 5c, J2-5 |
| SBOM (SPDX 2.3)   | Software Bill of Materials attached to images | 5c |
| GitHub Actions     | CI pipeline: Checkov + Trivy on every push/PR | J2-2 |
| Harbor             | Private container registry with OCI signature support | J2-5 |

### Runtime Security

| Tool    | Purpose                                           | Phase |
|---------|---------------------------------------------------|-------|
| Kyverno | Kubernetes admission controller — 7 ClusterPolicies (6 validate + 1 mutate), all Enforce | 6a, J2-5, Axe 3 |
| Vault   | Secrets injection via sidecar (Kubernetes auth, KV v2) | 6b |
| Falco   | Modern eBPF runtime threat detection (MITRE ATT&CK mapped) | 6c |
| Cilium NetworkPolicy | Pod-level ingress/egress firewall (deny-by-default) | 7b |

### Networking & Ingress

| Tool               | Purpose                                          | Phase  |
|--------------------|--------------------------------------------------|--------|
| Cilium Gateway API | L7 ingress controller (HTTPRoutes, TLS termination) | Axe 3 |
| cert-manager       | Automated TLS certificates (private CA + Let's Encrypt) | Axe 3, Axe 5 |
| Let's Encrypt      | Public TLS certificates via DNS-01 / Cloudflare  | Axe 5  |
| WireGuard          | Remote VPN access (built-in OPNsense 26)          | Axe 4  |
| Cloudflare DDNS    | Dynamic DNS for VPN endpoint (`vpn.ahaouari.com`) | Axe 4  |

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
| Image signing | Cosign key-based signing, verified at admission | Kyverno (`verify-image-signature`, **enforce**) |
| Network segmentation | NetworkPolicy: egress DNS + Vault only | Cilium |
| Secrets injection | Vault Agent sidecar, app never handles secrets | Vault + Kubernetes auth |
| Runtime detection | Shell-in-container detected in real time | Falco (T1059 MITRE ATT&CK) |
| TLS everywhere | Automated certificates via cert-manager | Let's Encrypt + private CA |

---

## Ingress — Cilium Gateway API + cert-manager

All HTTP services are routed through a single Cilium Gateway (`10.10.20.103`) using Kubernetes Gateway API. This replaces individual LoadBalancer IPs per service with hostname-based L7 routing, TLS termination by Envoy, and automatic HTTP-to-HTTPS redirection.

```
Client (browser / curl / phone via VPN)
  → DNS resolves hostname to 10.10.20.103 (Unbound override or /etc/hosts)
    → Cilium Gateway (Envoy) terminates TLS
      → HTTPRoute matches hostname → routes to backend Service
```

Two certificate issuers coexist in the cluster:

| Issuer | Type | Use case |
|--------|------|----------|
| `homelab-ca-issuer` | Private CA (self-signed) | Internal services (`*.homelab.local`, Harbor) |
| `letsencrypt-prod` | Let's Encrypt (DNS-01 via Cloudflare) | Public-facing services (`*.ahaouari.com`) |

cert-manager automatically provisions and renews TLS certificates. Let's Encrypt certificates are validated via DNS-01 challenges — cert-manager creates a temporary TXT record in Cloudflare, Let's Encrypt verifies domain ownership, then cert-manager cleans up. No web server is exposed to the internet.

**Kyverno mutate policy** — Cilium omits the `kubernetes.io/service-name` label on Gateway EndpointSlices, causing MetalLB to refuse ARP announcements. A Kyverno mutate policy (`mutate-gateway-endpointslice`) auto-injects the missing label, fixing the integration without manual intervention.

---

## Remote Access — WireGuard VPN + DDNS

The entire homelab is accessible from anywhere (phone on LTE, external laptop) via a WireGuard VPN tunnel through OPNsense.

```
Phone / Laptop (external network)
  → vpn.ahaouari.com:51820 (Cloudflare DDNS → public IP)
    → Port forward (Fizz router UDP 51820 → OPNsense WAN)
      → WireGuard tunnel (10.10.50.0/24)
        → OPNsense routes to internal VLANs (10.10.x.0/24)
          → Access ArgoCD, Grafana, Harbor, all services via VPN
```

| Component | Details |
|-----------|---------|
| VPN server | OPNsense 26 built-in WireGuard, port UDP 51820 |
| Tunnel subnet | `10.10.50.0/24` (virtual, not a VLAN) |
| DDNS | `vpn.ahaouari.com` updated by ddclient → Cloudflare API |
| Split tunnel | Only `10.10.0.0/16` and `192.168.0.0/24` routed through VPN |
| DNS via VPN | Clients use OPNsense Unbound (`10.10.20.1`) for internal resolution |

Split tunneling ensures that only traffic destined for the homelab flows through the VPN — regular internet traffic goes directly through the client's network.

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

**Outcome**: Rebuilt cluster from scratch in ~30 minutes using the IaC runbook — 4 nodes, ~71 pods, zero crashes.

### Test 3: Network Segmentation Audit (Hubble)

Hubble UI provided real-time visual proof of NetworkPolicy enforcement — forwarded flows (legitimate traffic on port 8080) and dropped flows (unauthorized access on port 9090) displayed on a live service map.

---

## CI/CD Pipeline — GitHub Actions

Every push and pull request to `main` triggers automated security scanning on infrastructure-as-code and Kubernetes manifests.

| Job | Tool | Scope | Failure mode |
|-----|------|-------|--------------|
| Checkov | bridgecrewio/checkov-action | `gitops/manifests/` — CIS benchmarks | `soft_fail: false` — pipeline fails on any finding |
| Trivy | aquasecurity/trivy-action | `gitops/manifests/` — HIGH/CRITICAL misconfigs | `exit-code: 1` — pipeline fails on findings |

Both jobs run in parallel on `ubuntu-latest`, triggered only on changes to `gitops/`, `terraform/`, `packer/`, or `ansible/` (path filters prevent unnecessary runs on docs or README changes).

Documented trade-offs are skipped in CI rather than lowering global severity: `CKV_K8S_38` (ServiceAccount token for Vault Agent), `CKV_K8S_35` (env var secret for distroless images), `CKV_K8S_40` (Redis UID 999 from official image).

---

## Microservices Application — Podinfo + Redis

A multi-tier cloud-native application deployed from scratch using the full security stack, with no tutorials — only documentation and prior knowledge from building the platform.

```
Namespace: podinfo
├── Podinfo (2 replicas, distroless)
│   ├── Port 9898 — HTTP API + UI + /metrics
│   ├── Secret delivery: SealedSecret → env var (distroless has no shell)
│   └── ServiceMonitor → Prometheus scrape every 15s
│
├── Redis (1 replica, Alpine + Vault Agent sidecar)
│   ├── Port 6379 — cache backend
│   └── Secret delivery: Vault Agent → file → sh -c exec redis-server
│
├── NetworkPolicies (zero-trust)
│   ├── Podinfo: ingress 9898, egress → Redis + DNS only
│   └── Redis: ingress 6379 from Podinfo only, egress → DNS + Vault + API server
│
└── Cache validated end-to-end: POST /cache/key → GET /cache/key
```

**Dual secret delivery** — the same Redis password lives in Vault (single source of truth) but is delivered through two different mechanisms depending on the image runtime: Vault Agent sidecar writes files for Alpine images (Redis), while SealedSecrets deliver env vars for distroless images (Podinfo) that have no shell to read files.

All containers pass the 7 Kyverno policies. Both images use digest pinning (no mutable tags).

---

## Persistent Storage — CSI Driver

Stateful workloads (Prometheus, Grafana, Loki) previously used `emptyDir` — data lost on every pod restart. `local-path-provisioner` (Rancher) solves this on Talos Linux where `/var/` is the only writable persistent path.

| Component | PVC | Size | Data persisted |
|-----------|-----|------|---------------|
| Prometheus | Bound | 10 Gi | TSDB metrics (7-day retention) |
| Grafana | Bound | 1 Gi | SQLite database (preferences, UI state) |
| Loki | Bound | 5 Gi | Log index and chunks (72h retention) |
| Harbor Registry | Bound | 10 Gi | Container image layers |
| Harbor PostgreSQL | Bound | 1 Gi | Harbor metadata |
| Harbor Redis | Bound | 1 Gi | Harbor cache |
| Harbor Jobservice | Bound | 1 Gi | Async job logs |

StorageClass `local-path` is marked as default with `WaitForFirstConsumer` binding. Data is node-local (SPOF) — acceptable trade-off for a homelab, documented.

---

## Harbor — Private Container Registry

Harbor provides a private, enterprise-grade container registry inside the cluster, replacing ghcr.io for image hosting. This resolved the last remaining security gap: Kyverno's `verify-image-signature` policy upgraded from **Audit** to **Enforce**.

```
Supply chain flow:
  Docker push → Harbor (private registry, self-signed TLS)
    → Cosign sign --key (key-based signature stored as OCI artifact)
      → Kyverno verify at admission (public key in policy, Enforce mode)
        → kubelet pull (Talos nodes trust Harbor CA via machine config)
```

**PKI trust distribution** — Harbor uses a self-signed CA certificate distributed to 4 trust boundaries: WSL system trust store, Windows certificate store (Docker Desktop), Talos machine config (containerd), and CoreDNS (cluster-internal hostname resolution via `harbor.homelab.local`).

**Key-based signing over keyless** — Cosign key-based signing was chosen over keyless (Sigstore OIDC) for the internal registry. Keyless depends on Fulcio/Rekor external services for verification; key-based verification is local and instantaneous using the public key embedded directly in the Kyverno policy. Keyless remains ideal for public CI/CD pipelines (GitHub Actions).

---

## Project Structure

```
homelab/
├── .github/
│   └── workflows/
│       └── security-scan.yaml       # CI: Checkov + Trivy on push/PR (path-filtered)
│
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
│   ├── monitoring/
│   │   ├── kube-prometheus-stack-values.yaml
│   │   ├── loki-stack-values.yaml
│   │   └── loki-datasource.yaml
│   ├── storage/
│   │   ├── local-path-storage.yaml  # CSI driver manifest
│   │   └── test-pvc.yaml
│   ├── harbor/
│   │   ├── harbor-values.yaml       # Helm values (resources, PVCs, TLS, MetalLB)
│   │   └── tls/                     # Self-signed CA + Harbor certificate
│   ├── cert-manager/
│   │   ├── clusterissuer.yaml       # Private CA issuer (homelab-ca-issuer)
│   │   ├── clusterissuer-letsencrypt.yaml  # Let's Encrypt DNS-01 via Cloudflare
│   │   └── certificates.yaml       # TLS certificates for *.homelab.local services
│   └── gateway/
│       ├── gateway.yaml             # Cilium Gateway (HTTP + HTTPS listeners)
│       ├── httproute-nginx.yaml     # nginx.homelab.local → nginx-test
│       ├── httproute-grafana.yaml   # grafana.homelab.local → monitoring/grafana
│       ├── httproute-hubble.yaml    # hubble.homelab.local → kube-system/hubble-ui
│       ├── httproute-podinfo.yaml   # podinfo.homelab.local → podinfo/podinfo-svc
│       └── httproute-redirect.yaml  # HTTP → HTTPS 301 redirect for all hostnames
│
├── cosign.pub                       # Cosign public key for image verification
│
└── gitops/                          # Phase 5+ — Everything deployed by ArgoCD
    ├── apps/                        # ArgoCD Application definitions (App of Apps)
    │   ├── nginx.yaml
    │   ├── kyverno-policies.yaml
    │   └── podinfo.yaml
    └── manifests/                   # Kubernetes manifests (source of truth)
        ├── nginx/
        │   ├── namespace.yaml
        │   ├── deployment.yaml      # Image from Harbor, signature verified by Kyverno
        │   ├── service.yaml
        │   ├── serviceaccount.yaml
        │   ├── sealedsecret.yaml
        │   └── networkpolicy.yaml
        ├── kyverno-policies/
        │   ├── disallow-latest-tag.yaml
        │   ├── require-run-as-nonroot.yaml
        │   ├── require-resource-limits.yaml
        │   ├── require-drop-all-capabilities.yaml
        │   ├── require-labels.yaml
        │   ├── verify-image-signature.yaml       # Enforce — key-based Cosign verification
        │   └── mutate-gateway-endpointslice.yaml # Auto-fix Cilium/MetalLB label bug
        ├── podinfo/
        │   ├── namespace.yaml
        │   ├── serviceaccount-podinfo.yaml
        │   ├── serviceaccount-redis.yaml
        │   ├── deployment-podinfo.yaml
        │   ├── deployment-redis.yaml
        │   ├── service-podinfo.yaml
        │   ├── service-redis.yaml
        │   ├── networkpolicy-podinfo.yaml
        │   ├── networkpolicy-redis.yaml
        │   ├── sealedsecret-redis-url.yaml
        │   └── servicemonitor.yaml
        └── rexpn/
            └── httproute-rexpn.yaml  # rexpn.ahaouari.com (Let's Encrypt TLS)
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
- [x] **Phase 6a** — Policy enforcement: Kyverno (7 ClusterPolicies — 6 validate + 1 mutate, all Enforce)
- [x] **Phase 6b** — Secrets management: HashiCorp Vault (KV v2, Kubernetes auth, sidecar injection)
- [x] **Phase 6c** — Runtime security: Falco (modern eBPF, MITRE ATT&CK mapped, Falcosidekick)
- [x] **Phase 7a** — Observability: Prometheus + Grafana (20+ dashboards), Loki + Promtail
- [x] **Phase 7b** — Network segmentation: Cilium NetworkPolicies + attack scenario validation
- [x] **Phase J2-1** — Chaos engineering: self-heal, node failure resilience, Hubble network audit
- [x] **Phase J2-2** — CI/CD pipeline: GitHub Actions with Checkov + Trivy (path-filtered, parallel jobs)
- [x] **Phase J2-3** — Microservices: Podinfo + Redis with dual secret delivery (Vault + SealedSecrets), NetworkPolicies, ServiceMonitor
- [x] **Phase J2-4** — Persistent storage: local-path-provisioner CSI driver, PVCs for Prometheus (10Gi), Grafana (1Gi), Loki (5Gi)
- [x] **Phase J2-5** — Harbor private registry: Cosign key-based signing, Kyverno image verification upgraded from Audit to Enforce, self-signed PKI
- [x] **Axe 3** — Ingress: Cilium Gateway API (L7 routing, TLS termination), cert-manager (private CA + Let's Encrypt), HTTP→HTTPS redirect
- [x] **Axe 4** — Remote access: WireGuard VPN via OPNsense, Cloudflare DDNS (`vpn.ahaouari.com`), split tunnel
- [x] **Axe 5** — Public TLS: Let's Encrypt certificates via DNS-01 / Cloudflare, split-horizon DNS for internal resolution

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

# 3. Install Gateway API CRDs (required before Cilium)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/experimental/gateway.networking.k8s.io_grpcroutes.yaml

# 4. Install networking (with Gateway API enabled)
helm install cilium cilium/cilium --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445 \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set gatewayAPI.enabled=true
helm install metallb metallb/metallb --namespace metallb-system --create-namespace \
  --set speaker.frr.enabled=false

# 5. Install persistent storage (before monitoring stack)
kubectl apply -f kubernetes/storage/local-path-storage.yaml

# 6. Install GitOps (ArgoCD syncs everything else from Git)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  --server-side --force-conflicts
argocd app create root --repo https://github.com/abdelhaouari/homelab.git \
  --path gitops/apps --sync-policy automated --auto-prune --self-heal

# 7. Install security stack
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace \
  --set "features.registryClient.allowInsecure=true"
helm install vault hashicorp/vault --namespace vault --create-namespace \
  --set server.dev.enabled=true --set injector.enabled=true
helm install falco falcosecurity/falco --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=false

# 8. Install cert-manager + Gateway
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace \
  --set crds.enabled=true
# Create CA secret and Cloudflare API token secret in cert-manager namespace
# Apply ClusterIssuers, Certificates, Gateway, and HTTPRoutes

# 9. Install Harbor (private container registry)
helm install harbor harbor/harbor --namespace harbor \
  --values kubernetes/harbor/harbor-values.yaml --version 1.16.2

# 10. Install observability
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
  → GitHub Actions runs Checkov + Trivy (shift-left gate)
    → ArgoCD detects change (polling or webhook)
      → Manifests are applied to the cluster
        → Kyverno validates at admission (blocks non-compliant or unsigned images)
          → Vault Agent injects secrets into pods
            → Cilium Gateway routes traffic via HTTPRoutes (TLS terminated)
              → Falco monitors runtime behavior
                → Prometheus scrapes metrics, Promtail collects logs
                  → Grafana displays dashboards and alerts
```

To deploy a new application:
1. Add Kubernetes manifests to `gitops/manifests/<app>/`
2. Add an ArgoCD Application definition to `gitops/apps/<app>.yaml`
3. Create an HTTPRoute for the Cilium Gateway (if HTTP access is needed)
4. `git commit && git push` — ArgoCD handles the rest

Manual changes to the cluster are automatically reverted by ArgoCD's self-heal.

---

## Security Principles

| Principle | Implementation |
|-----------|---------------|
| Least privilege | Per-tool API tokens, PodSecurity labels per namespace, RBAC scoped to namespace |
| Immutable infrastructure | Packer golden images, Talos Linux (no SSH, no shell, API-only) |
| Secrets management | Sealed Secrets for Git, Vault sidecar injection at runtime, `.gitignore` for local secrets |
| Network segmentation | VLANs (OPNsense), Cilium NetworkPolicies (deny-by-default egress), WireGuard split tunnel |
| Defense in depth | Perimeter FW → VLAN isolation → PodSecurity → Kyverno admission → NetworkPolicy → Falco runtime |
| Shift-left security | Trivy + Checkov scan manifests and images before deployment |
| Supply chain security | Cosign key-based signing, Harbor private registry, digest pinning (no mutable tags) |
| TLS everywhere | cert-manager automates certificates — private CA for internal, Let's Encrypt for public |
| GitOps | Git is the single source of truth; drift is auto-corrected |
| Audit trail | Git commit history, Kubernetes audit logs, Falco alerts in Loki/Grafana |
| Reproducibility | Full destroy and rebuild from code in ~30 minutes |
| Remote access | WireGuard VPN with split tunnel — no services exposed to the internet |

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
| Cilium Gateway API | L7 ingress controller (HTTPRoutes) | Deployed |
| MetalLB | Bare-metal load balancer (L2/ARP, FRR disabled) | Deployed |
| ArgoCD | GitOps continuous delivery | Deployed |
| Sealed Secrets | Encrypted secrets in Git | Deployed |
| Trivy | CVE + IaC scanner | Deployed |
| Checkov | IaC security scanner (CIS) | Deployed |
| Cosign (Sigstore) | Image signing + verification | Deployed |
| Kyverno | Policy enforcement (admission + mutation) | Deployed |
| HashiCorp Vault | Secrets management | Deployed |
| Falco | Runtime threat detection (modern eBPF) | Deployed |
| Prometheus + Grafana | Metrics + dashboards | Deployed |
| Loki + Promtail | Log aggregation | Deployed |
| GitHub Actions | CI/CD security pipeline | Deployed |
| local-path-provisioner | CSI driver / persistent storage | Deployed |
| Harbor | Private container registry | Deployed |
| cert-manager | TLS certificate automation | Deployed |
| Let's Encrypt | Public TLS certificates (DNS-01) | Deployed |
| WireGuard | Remote access VPN (OPNsense built-in) | Deployed |
| Cloudflare DDNS | Dynamic DNS for VPN endpoint | Deployed |
