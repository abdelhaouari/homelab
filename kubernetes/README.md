# Kubernetes — Helm Values & Monitoring Configuration

This directory contains Helm values files and configuration manifests for components installed manually via `helm install` (not managed by ArgoCD).

## Why Not ArgoCD?

Components in this directory are **infrastructure-level dependencies** that must exist before ArgoCD can function, or were installed during the learning phase via CLI. In a more mature setup, these could be wrapped in ArgoCD Applications with Helm source type.

| Component            | Why manual                                              |
|----------------------|---------------------------------------------------------|
| Cilium               | CNI must exist before any pod networking works          |
| MetalLB              | LoadBalancer IPs needed before ArgoCD can be exposed    |
| ArgoCD               | Chicken-and-egg — can't deploy itself via GitOps        |
| Sealed Secrets       | Required for ArgoCD to decrypt secrets on first sync    |
| Kyverno              | Admission controller, installed before app deployments  |
| Vault                | Secret injection infrastructure                         |
| Falco                | Runtime detection, infrastructure-level DaemonSet       |
| Prometheus + Grafana | Observability stack, installed via Helm                  |
| Loki + Promtail      | Log aggregation, installed via Helm                      |

## Directory Structure

```
kubernetes/
├── README.md
└── monitoring/
    ├── kube-prometheus-stack-values.yaml    # Prometheus, Grafana, Alertmanager
    ├── loki-stack-values.yaml              # Loki, Promtail
    └── loki-datasource.yaml               # Grafana datasource ConfigMap
```

## Monitoring Stack

### kube-prometheus-stack (v72.3.0)

Deploys Prometheus, Grafana, Alertmanager, node-exporter, and kube-state-metrics.

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values kubernetes/monitoring/kube-prometheus-stack-values.yaml \
  --version 72.3.0
```

**Key values:**
- Grafana exposed as `LoadBalancer` via MetalLB (`10.10.20.103`)
- No PersistentVolumes (emptyDir) — data lost on pod restart, acceptable for lab
- ServiceMonitors disabled for components not scrapable on Talos (kube-proxy, etcd, scheduler, controller-manager)
- 7-day retention for metrics

### Loki Stack (v2.10.2)

Deploys Loki (log storage) and Promtail (log collection DaemonSet).

```bash
helm install loki-stack grafana/loki-stack \
  --namespace monitoring \
  --values kubernetes/monitoring/loki-stack-values.yaml \
  --version 2.10.2
```

**Key values:**
- Promtail URL must use FQDN: `http://loki-stack.monitoring:3100/loki/api/v1/push`
- 72-hour log retention (memory is limited at ~86% utilization)
- No persistence (emptyDir)

### Loki Datasource

Grafana discovers datasources via a sidecar that watches ConfigMaps with the label `grafana_datasource: "1"`.

```bash
kubectl apply -f kubernetes/monitoring/loki-datasource.yaml
```

If the sidecar doesn't detect it immediately, restart Grafana:
```bash
kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
```

## Namespace Configuration

The `monitoring` namespace requires PodSecurity `privileged` because node-exporter and Promtail need host-level access:

```bash
kubectl create namespace monitoring
kubectl label namespace monitoring \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged
```

## Grafana Access

| Field     | Value                         |
|-----------|-------------------------------|
| URL       | `http://10.10.20.103`         |
| Username  | `admin`                       |
| Password  | Defined in Helm values        |
| Dashboards| ~20 kubernetes-mixin (pre-installed) |
| Datasources| Prometheus (default), Loki, Alertmanager |

> **Note:** Without PersistentVolumes, Grafana loses imperative state (password changes, manual dashboards) on restart. Declarative state from ConfigMaps and Helm values is preserved.
