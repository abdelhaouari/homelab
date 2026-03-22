# Ansible - Configuration Management

Post-deployment configuration for all lab VMs using Ansible. This layer sits after Terraform in the IaC pipeline and enforces a consistent security baseline across all managed hosts.

## Pipeline Position

```
Packer (golden image) → Terraform (VM provisioning) → Ansible (configuration) ← you are here
```

## Quick Start

```bash
# Test connectivity to all hosts
ansible all -m ping

# Dry run (simulate changes without applying)
ansible-playbook site.yml --check --diff

# Apply configuration
ansible-playbook site.yml
```

## Inventory

Hosts are organized by cluster role in `inventory/hosts.yml`:

| Group | Hosts | Purpose |
|-------|-------|---------|
| `k8s_cluster` | All nodes | Target for shared configuration (baseline hardening) |
| `control_plane` | k8s-ctrl-01 | Kubernetes control plane nodes |
| `workers` | k8s-work-01, k8s-work-02 | Kubernetes worker nodes |

## Roles

### `baseline` - Security Hardening

Applies an enterprise-grade security baseline to any Ubuntu server. Fully idempotent - safe to run repeatedly.

**What it configures:**

| Layer | Tool | Purpose |
|-------|------|---------|
| System updates | APT | Full system upgrade with cache optimization |
| Host firewall | UFW | Default deny incoming, explicit port allowlist |
| Brute-force protection | Fail2Ban | Monitors SSH logs, auto-bans after failed attempts |
| Kernel hardening | sysctl | Disables IP forwarding, ICMP redirects, source routing; enables SYN cookies and reverse path filtering |
| Audit trail | auditd | Watches identity files, sudoers, firewall binaries, and time-change syscalls |

**Customizable variables** (defined in `roles/baseline/defaults/main.yml`):

| Variable | Default | Description |
|----------|---------|-------------|
| `security_baseline_packages` | `[ufw, fail2ban, auditd, unattended-upgrades]` | Packages to install |
| `ufw_allowed_ports` | `[{port: 22, proto: tcp}]` | Firewall port allowlist |
| `fail2ban_bantime` | `3600` | Ban duration in seconds |
| `fail2ban_findtime` | `600` | Failure counting window in seconds |
| `fail2ban_maxretry` | `3` | Max failures before ban |
| `sysctl_security_params` | *(see defaults)* | Kernel network hardening parameters |

**Important:** `net.ipv4.ip_forward` is set to `0` by default. This must be overridden to `1` for any host running Kubernetes (pod networking requires IP forwarding).

## File Structure

```
ansible/
├── ansible.cfg              # Local Ansible configuration (inventory path, SSH settings)
├── site.yml                 # Main playbook - entry point for all configuration
├── inventory/
│   └── hosts.yml            # Host inventory grouped by cluster role
└── roles/
    └── baseline/            # Security hardening role
        ├── defaults/main.yml    # Overridable default variables
        ├── tasks/main.yml       # Task definitions
        ├── handlers/main.yml    # Service restart handlers
        ├── templates/           # Jinja2 config templates (Fail2Ban, sysctl)
        └── files/               # Static files (auditd rules)
```

## Design Decisions

- **Agentless architecture** - Ansible connects via SSH; nothing is installed on target hosts. This is why Ansible will not be used for Talos Linux nodes (no SSH access on immutable OS).
- **Role-based organization** - Each concern is a self-contained role, reusable across different host groups and future VMs (monitoring servers, jump hosts, security lab).
- **Defense in depth** - Host-level security (UFW, sysctl, auditd) complements network-level security (OPNsense VLAN segmentation). Compromise of one layer does not compromise the other.
- **Idempotency verified** - Second run produces `changed=0` across all hosts, confirming the role describes desired state rather than a sequence of actions.
