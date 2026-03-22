# Baseline Security Hardening Role

Ansible role that applies a standard security baseline to Ubuntu servers. Designed to be the first role applied to any new machine in the lab, establishing a consistent security posture before any application-specific configuration.

## What This Role Does

1. **System Updates** - Updates APT cache and performs a full system upgrade (with `cache_valid_time` to avoid redundant network calls).
2. **Security Packages** - Installs UFW, Fail2Ban, auditd, and unattended-upgrades.
3. **Host Firewall (UFW)** - Sets default deny incoming / allow outgoing policy, opens only explicitly listed ports, and enables the firewall.
4. **Brute-Force Protection (Fail2Ban)** - Deploys a `jail.local` configuration with tunable ban parameters and enables the `sshd` jail.
5. **Kernel Hardening (sysctl)** - Deploys hardened network stack parameters to `/etc/sysctl.d/99-security-hardening.conf`.
6. **Audit Framework (auditd)** - Deploys rules to monitor identity files, privilege escalation, firewall manipulation, and time-change syscalls.

## Requirements

- Target hosts must run Ubuntu (tested on 24.04 LTS)
- SSH access with a user that has passwordless sudo (`NOPASSWD`)
- Python 3 on target hosts (for Ansible module execution)

## Role Variables

All variables are defined in `defaults/main.yml` and can be overridden in inventory, group_vars, or playbook scope.

### Packages

```yaml
security_baseline_packages:
  - ufw
  - fail2ban
  - auditd
  - unattended-upgrades
```

### UFW

```yaml
ufw_allowed_ports:
  - { port: 22, proto: tcp, comment: "Allow SSH access for Ansible and Admins" }
```

### Fail2Ban

```yaml
fail2ban_bantime: 3600    # 1 hour ban
fail2ban_findtime: 600    # 10 minute window
fail2ban_maxretry: 3      # 3 strikes
```

### Sysctl

```yaml
sysctl_security_params:
  net.ipv4.ip_forward: 0                       # Disable packet forwarding
  net.ipv4.conf.all.accept_redirects: 0         # Ignore ICMP redirects
  net.ipv4.conf.all.accept_source_route: 0      # Disable source routing
  net.ipv4.tcp_syncookies: 1                     # SYN flood protection
  net.ipv4.conf.all.rp_filter: 1                 # Reverse path filtering (anti-spoofing)
```

> **Note:** `net.ipv4.ip_forward` must be overridden to `1` for Kubernetes nodes, as pod networking (CNI) requires IP forwarding between interfaces.

## Handlers

| Handler | Triggered by | Action |
|---------|-------------|--------|
| Restart Fail2Ban | `jail.local` template change | `systemctl restart fail2ban` |
| Reload sysctl config | sysctl template change | `sysctl --system` |
| Reload auditd rules | audit rules file change | `augenrules --load` (hot reload, no audit gap) |

## Example Playbook

```yaml
- name: Apply baseline security hardening
  hosts: k8s_cluster
  roles:
    - baseline
```

## License

MIT

## Author

Built as part of a DevSecOps home lab project.
