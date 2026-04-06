# Architecture Overview

This document describes the infrastructure, network design, and security architecture of the homelab platform.

## Infrastructure

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Physical Host                                 │
│                   Intel Xeon E5-1650 v3 (6C/12T)                     │
│                   64 GB DDR4 · ZFS RAIDZ-1 (~916 GB)                 │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                    Proxmox VE 9.1.6                             │ │
│  │                                                                 │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐         │ │
│  │  │ OPNsense │  │ talos    │  │ talos    │  │ talos    │         │ │
│  │  │ VM 100   │  │ ctrl-01  │  │ work-01  │  │ work-02  │         │ │
│  │  │          │  │ VM 201   │  │ VM 202   │  │ VM 203   │         │ │
│  │  │ WAN+LAN  │  │ 2C/4GB   │  │ 2C/4GB   │  │ 2C/4GB   │         │ │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘         │ │
│  │       │              │              │              │            │ │
│  │  ┌────┴──────────────┴──────────────┴──────────────┴────────┐   │ │
│  │  │                vmbr1 (VLAN-aware bridge)                 │   │ │
│  │  │            VIDs: 10, 20, 30, 40 · No physical port       │   │ │
│  │  └──────────────────────────────────────────────────────────┘   │ │
│  │  ┌──────────────────────────────────────────────────────────┐   │ │
│  │  │                vmbr0 (Physical bridge)                   │   │ │
│  │  │              192.168.0.0/24 · nic0                       │   │ │
│  │  └──────────────────────┬───────────────────────────────────┘   │ │
│  └─────────────────────────┼───────────────────────────────────────┘ │
└────────────────────────────┼─────────────────────────────────────────┘
                             │
                    ┌────────┴────────┐
                    │  ISP Router     │
                    │  192.168.0.1    │
                    └────────┬────────┘
                             │
                         Internet
```

## Network Segmentation

OPNsense acts as a router-on-a-stick, routing between VLANs via sub-interfaces on `vtnet1` (connected to `vmbr1`).

```
                        ┌─────────────────────┐
                        │      OPNsense       │
                        │   WAN: 192.168.0.210│
                        │                     │
                        │  vtnet1 (trunk)     │
                        │  ├─ VLAN 10 MGMT    │ 10.10.10.1
                        │  ├─ VLAN 20 K8S     │ 10.10.20.1
                        │  ├─ VLAN 30 STORAGE │ 10.10.30.1
                        │  └─ VLAN 40 LAB     │ 10.10.40.1
                        └─────────────────────┘
```

| Zone        | VLAN | Subnet         | Purpose                                |
|-------------|------|----------------|----------------------------------------|
| Management  | 10   | 10.10.10.0/24  | Admin access, future monitoring VMs    |
| Kubernetes  | 20   | 10.10.20.0/24  | K8s nodes, services, MetalLB pool      |
| Storage     | 30   | 10.10.30.0/24  | Persistent storage backends (future)   |
| Lab / DMZ   | 40   | 10.10.40.0/24  | Isolated security lab (future)         |

### VLAN 20 — Kubernetes IP Allocation

| Range              | Purpose                           |
|--------------------|-----------------------------------|
| 10.10.20.1         | OPNsense gateway                  |
| 10.10.20.10–12     | Talos nodes (static IPs)          |
| 10.10.20.100–150   | MetalLB pool (LoadBalancer IPs)   |
| 10.10.20.200–250   | OPNsense Kea DHCP (maintenance)   |
| 10.244.0.0/16      | Pod subnet (virtual, Cilium)      |
| 10.96.0.0/12       | Service subnet (ClusterIPs)       |

### Exposed Services (MetalLB L2/ARP)

| IP             | Service     | Protocol |
|----------------|-------------|----------|
| 10.10.20.100   | Hubble UI   | HTTP     |
| 10.10.20.101   | ArgoCD UI   | HTTPS    |
| 10.10.20.102   | nginx-test  | HTTP     |
| 10.10.20.103   | Grafana     | HTTP     |

### Routing

```
Windows (192.168.0.13) ──► route add 10.10.0.0/16 via 192.168.0.210
                                          │
                                    OPNsense WAN
                                          │
                               Inter-VLAN routing
                                          │
                              ┌───────────┼───────────┐
                              │           │           │
                         VLAN 10     VLAN 20     VLAN 30/40
```

## Kubernetes Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (Talos Linux)                 │
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │
│  │  talos-ctrl-01  │  │  talos-work-01  │  │  talos-work-02  │      │
│  │  10.10.20.10    │  │  10.10.20.11    │  │  10.10.20.12    │      │
│  │                 │  │                 │  │                 │      │
│  │  API Server     │  │  Cilium Agent   │  │  Cilium Agent   │      │
│  │  etcd           │  │  Cilium Envoy   │  │  Cilium Envoy   │      │
│  │  Scheduler      │  │  node-exporter  │  │  node-exporter  │      │
│  │  Controller Mgr │  │  Promtail       │  │  Promtail       │      │
│  │  Cilium Agent   │  │  MetalLB Spkr   │  │  MetalLB Spkr   │      │
│  │  Cilium Envoy   │  │  Falco          │  │  Falco          │      │
│  │  node-exporter  │  │                 │  │                 │      │
│  │  Promtail       │  │  ┌───────────┐  │  │  ┌───────────┐  │      │
│  │  MetalLB Spkr   │  │  │nginx x3   │  │  │  │nginx x3   │  │      │
│  │  Falco          │  │  │+vault-agent│ │  │  │+vault-agent│ │      │
│  │  Hubble Relay   │  │  └───────────┘  │  │  └───────────┘  │      │
│  │  Hubble UI      │  │                 │  │                 │      │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘      │
│                                                                     │
│  Namespaces:                                                        │
│  ├── kube-system    Cilium, CoreDNS, Sealed Secrets                 │
│  ├── argocd         ArgoCD (7 components)                           │
│  ├── metallb-system MetalLB controller + speakers                   │
│  ├── nginx-test     Hardened nginx + Vault Agent sidecar            │
│  ├── kyverno        Admission controller (4 components)             │
│  ├── vault          Vault server + Agent Injector                   │
│  ├── falco          Runtime detection + Falcosidekick               │
│  └── monitoring     Prometheus, Grafana, Alertmanager, Loki         │
└─────────────────────────────────────────────────────────────────────┘
```

## Security Architecture — Defense in Depth

Each layer operates independently. An attacker must defeat ALL layers.

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1 — Network Perimeter                                    │
│  ISP Router (NAT) → OPNsense (VLAN segmentation, firewall)      │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2 — Host Security                                        │
│  Talos Linux (immutable OS, no SSH, no shell, API-only)         │
│  mTLS on all cluster communications · etcd encryption at rest   │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3 — Admission Control                                    │
│  Kyverno (6 policies) · PodSecurity labels per namespace        │
│  Blocks: latest tags, root containers, missing limits/caps      │
├─────────────────────────────────────────────────────────────────┤
│  Layer 4 — Network Segmentation                                 │
│  Cilium NetworkPolicies (deny-by-default egress)                │
│  Blocks: lateral movement, internet exfiltration                │
├─────────────────────────────────────────────────────────────────┤
│  Layer 5 — Runtime Hardening                                    │
│  securityContext: non-root, read-only FS, drop ALL caps         │
│  Vault Agent sidecar: app never handles secrets directly        │
├─────────────────────────────────────────────────────────────────┤
│  Layer 6 — Detection & Response                                 │
│  Falco: eBPF runtime detection (MITRE ATT&CK mapped)            │
│  Prometheus + Loki + Grafana: centralized metrics and logs      │
├─────────────────────────────────────────────────────────────────┤
│  Layer 7 — Supply Chain                                         │
│  Trivy + Checkov: shift-left scanning                           │
│  Cosign: keyless image signing (Sigstore)                       │
│  SBOM: Software Bill of Materials (SPDX 2.3)                    │
├─────────────────────────────────────────────────────────────────┤
│  Layer 8 — GitOps / Drift Prevention                            │
│  ArgoCD: self-heal reverts unauthorized cluster changes         │
│  Sealed Secrets: encrypted secrets safe for public Git          │
│  Git history: audit trail for every deployment                  │
└─────────────────────────────────────────────────────────────────┘
```

## GitOps Data Flow

```
Developer (WSL)
    │
    │  git push
    ▼
GitHub (public repo)
    │
    │  ArgoCD polls (every 3 min)
    ▼
ArgoCD (in-cluster)
    │
    ├── Compares Git manifests vs cluster state
    ├── Applies diff (create/update/delete resources)
    ├── Kyverno validates at admission
    │     └── Rejects non-compliant pods
    ├── Sealed Secrets controller decrypts secrets
    ├── Vault Agent injects runtime secrets into pods
    │
    ▼
Running Pods
    │
    ├── Falco monitors syscalls (eBPF)
    ├── Prometheus scrapes /metrics
    ├── Promtail ships logs to Loki
    └── Cilium enforces NetworkPolicies
```

## IaC Pipeline

Two parallel pipelines exist in this repo:

### Active Pipeline — Kubernetes (Talos)
```
Terraform (bpg/proxmox)
    │  provisions 3 VMs from Talos image
    ▼
talosctl gen config
    │  generates machine configs + PKI
    ▼
talosctl apply-config
    │  configures each node (IP, hostname, patches)
    ▼
talosctl bootstrap
    │  initializes etcd + control plane
    ▼
Helm installs (Cilium, MetalLB, ArgoCD, Kyverno, Vault, Falco, Prometheus, Loki)
    │
    ▼
ArgoCD root app (App of Apps)
    │  syncs all applications from gitops/
    ▼
Running cluster with full security stack
```

### Auxiliary Pipeline — Ubuntu VMs (Packer + Ansible)
```
Packer (proxmox-iso builder)
    │  builds hardened Ubuntu 24.04 golden image
    │  air-gapped autoinstall, OS hardening provisioner
    ▼
Proxmox Template (ID 9000)
    │
    ▼
Terraform (bpg/proxmox)
    │  clones template, Cloud-Init (IPs, SSH keys)
    ▼
Ansible (baseline role)
    │  UFW, Fail2Ban, sysctl, auditd
    ▼
Hardened Ubuntu VM (ready for non-K8s workloads)
```

This pipeline is preserved in the repo but the Ubuntu VMs are currently destroyed. It's reusable for future non-Kubernetes VMs (monitoring server, SIEM, jump host).

## Storage Architecture

| Storage     | Type    | Content                               |
|-------------|---------|---------------------------------------|
| `local`     | dir     | ISOs, templates, backups, snippets    |
| `local-zfs` | zfspool | VM disks, container rootdirs          |

> **No `local-lvm`** — this Proxmox uses ZFS exclusively. Terraform must reference `local-zfs` for disk storage.

## Proxmox Hardening

| Control                    | Implementation                              |
|----------------------------|---------------------------------------------|
| Admin user                 | `admin@pve` (PVE realm, not PAM)            |
| 2FA                        | TOTP on `admin@pve`                         |
| API token                  | `admin@pve!packer` (PVEAdmin role on `/`)   |
| SSH                        | Port 2222, Ed25519 key only, no password    |
