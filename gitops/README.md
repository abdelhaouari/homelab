# GitOps — ArgoCD Application Deployments

This directory is the **single source of truth** for all application deployments managed by ArgoCD. Every file here is continuously reconciled against the live cluster state.

## How It Works

ArgoCD uses the **App of Apps pattern**: a single root Application watches `gitops/apps/` and automatically creates child Applications for each YAML file it finds. Each child Application points to a directory in `gitops/manifests/` containing the actual Kubernetes manifests.

```
Root Application (created once, manually)
│
│  watches: gitops/apps/
│
├── nginx.yaml ──────────► Application "nginx"
│                              watches: gitops/manifests/nginx/
│                              deploys: namespace, deployment, service,
│                                       serviceaccount, sealedsecret, networkpolicy
│
└── kyverno-policies.yaml ► Application "kyverno-policies"
                               watches: gitops/manifests/kyverno-policies/
                               deploys: 6 ClusterPolicies
```

## Directory Structure

```
gitops/
├── apps/                              # ArgoCD Application definitions
│   ├── nginx.yaml                     # → gitops/manifests/nginx/
│   └── kyverno-policies.yaml          # → gitops/manifests/kyverno-policies/
│
└── manifests/                         # Kubernetes manifests (deployed by ArgoCD)
    ├── nginx/                         # Hardened test application
    │   ├── namespace.yaml             # Namespace nginx-test
    │   ├── deployment.yaml            # 3 replicas, fully hardened (see below)
    │   ├── service.yaml               # LoadBalancer → MetalLB (10.10.20.102)
    │   ├── serviceaccount.yaml        # nginx-sa (Vault Kubernetes auth)
    │   ├── sealedsecret.yaml          # Encrypted credentials (Sealed Secrets)
    │   └── networkpolicy.yaml         # Ingress port 8080, egress DNS+Vault only
    │
    └── kyverno-policies/              # Cluster-wide security policies
        ├── disallow-latest-tag.yaml          # Enforce — no :latest
        ├── require-run-as-nonroot.yaml       # Enforce — must be non-root
        ├── require-resource-limits.yaml      # Enforce — CPU/memory limits
        ├── require-drop-all-capabilities.yaml # Enforce — drop ALL caps
        ├── require-labels.yaml               # Enforce — app label required
        └── verify-image-signature.yaml       # Audit — Cosign keyless verification
```

## Deploying a New Application

To add a new application to the cluster:

**1. Create the manifests:**
```bash
mkdir -p gitops/manifests/my-app
# Create namespace.yaml, deployment.yaml, service.yaml, etc.
```

**2. Create the ArgoCD Application definition:**
```yaml
# gitops/apps/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/abdelhaouari/homelab.git
    targetRevision: main
    path: gitops/manifests/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**3. Commit and push:**
```bash
git add gitops/
git commit -m "feat(my-app): add application deployment"
git push
```

ArgoCD detects the new Application definition within ~3 minutes and deploys the manifests automatically. No `kubectl apply` needed.

## Sync Policy

All Applications use the same sync policy:

| Setting        | Value   | Effect                                                  |
|----------------|---------|---------------------------------------------------------|
| `automated`    | `true`  | Sync automatically when Git changes                     |
| `prune`        | `true`  | Resources deleted from Git are deleted from the cluster  |
| `selfHeal`     | `true`  | Manual cluster changes are reverted to match Git         |
| `CreateNamespace` | `true` | Target namespace is created if it doesn't exist       |

**`selfHeal` is a security control** — if someone runs `kubectl edit` or `kubectl scale` to modify a deployment, ArgoCD reverts the change within seconds.

## Nginx Deployment — Security Hardening

The nginx deployment in `manifests/nginx/deployment.yaml` implements every security best practice:

| Control | Implementation |
|---------|---------------|
| Non-root | `runAsNonRoot: true`, `runAsUser: 10001` |
| Read-only filesystem | `readOnlyRootFilesystem: true` + emptyDir for `/tmp`, `/var/cache/nginx`, `/var/run` |
| Drop all capabilities | `capabilities.drop: ["ALL"]` |
| No privilege escalation | `allowPrivilegeEscalation: false` |
| Seccomp | `seccompProfile.type: RuntimeDefault` |
| Resource limits | CPU 50m–100m, memory 64Mi–128Mi |
| Image pinning | Digest-pinned (`@sha256:...`), no mutable tags |
| Health probes | `livenessProbe` + `readinessProbe` on port 8080 |
| Secrets injection | Vault Agent sidecar via annotations |
| Network segmentation | NetworkPolicy: egress DNS + Vault only |

This deployment passes all Trivy and Checkov checks except `CKV_K8S_38` (ServiceAccount token), which is a documented trade-off required for Vault Agent authentication.

## Kyverno Policies

Six ClusterPolicies enforce security standards across the cluster:

| Policy | Mode | Severity | What it blocks |
|--------|------|----------|----------------|
| `disallow-latest-tag` | Enforce | Medium | Images using `:latest` tag |
| `require-run-as-nonroot` | Enforce | High | Containers without `runAsNonRoot: true` |
| `require-resource-limits` | Enforce | Medium | Containers without CPU/memory limits |
| `require-drop-all-capabilities` | Enforce | Medium | Containers that don't drop ALL capabilities |
| `require-labels` | Enforce | Low | Pods without the `app` label |
| `verify-image-signature` | Audit | High | Images not signed with Cosign (GHCR limitation) |

**Excluded namespaces**: `kube-system`, `kyverno`, `metallb-system`, `argocd` — system components that may not comply with all policies.

## Sealed Secrets

The `sealedsecret.yaml` in `manifests/nginx/` contains encrypted credentials. Only the Sealed Secrets controller inside the cluster can decrypt them.

**To seal a new secret:**
```bash
kubectl create secret generic my-secret \
  --from-literal=KEY=value \
  --dry-run=client -o yaml | \
kubeseal --format yaml > gitops/manifests/my-app/sealedsecret.yaml

# Commit the SealedSecret (safe for public repo)
# DELETE any plaintext secret files immediately
```

## Root Application Setup

The root application is the **only manual ArgoCD operation**. Run once after ArgoCD is installed:

```bash
argocd app create root \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace argocd \
  --repo https://github.com/abdelhaouari/homelab.git \
  --path gitops/apps \
  --revision main \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

After this, all changes flow through Git.
