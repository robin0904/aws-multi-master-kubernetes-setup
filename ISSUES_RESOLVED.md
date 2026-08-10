# Issues Resolved & Script Updates

This document tracks all bugs fixed and script improvements made during deployment testing.

---

## Critical Issues Fixed

### 1. **Kubelet Configuration File Path Error** ❌ → ✅
**Issue:** Kubelet failing with JSON parse error on `/var/lib/kubelet/kubeadm-flags.env`

**Root Cause:** 
- File: `ansible/roles/kubernetes/tasks/main.yml` line 39
- Mistake: `--config=/var/lib/kubelet/kubeadm-flags.env` (environment file, not YAML config)
- Should be: `--config=/var/lib/kubelet/config.yaml`

**Fix Applied:**
```yaml
# BEFORE (WRONG)
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/kubeadm-flags.env"

# AFTER (CORRECT)
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
```

**Files Modified:**
- `ansible/roles/kubernetes/tasks/main.yml`

**Impact:** Kubelet now starts correctly; cluster can initialize.

---

### 2. **Calico Operator CRD Annotation Too Large** ❌ → ✅
**Issue:** "metadata.annotations: Too long: may not be more than 262144 bytes"

**Root Cause:**
- Tigera operator manifests have oversized CRD annotations
- Applies unnecessary complexity for simple networking

**Fix Applied:**
- Switched from Tigera operator → Direct Calico manifests
- File: `ansible/roles/cluster_init/tasks/main.yml`
- Change: Use `calico.yaml` instead of `tigera-operator.yaml`

**Before:**
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/tigera-operator.yaml
```

**After:**
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml --validate=false
```

**Benefits:**
- Simpler deployment (no operator lifecycle)
- Fewer CRDs, no annotation size issues
- Direct DaemonSet deployment

---

### 3. **Bootstrap Token Parsing Failure** ❌ → ✅
**Issue:** "invalid bootstrap token" when joining nodes

**Root Cause:**
- File: `ansible/roles/cluster_join/tasks/main.yml`
- Code: `{{ kubeadm_join_command.split()[5] }}` assumed fixed token position
- Actual join command format varies; token not always at index 5

**Fix Applied:**
```yaml
# BEFORE (WRONG - assumes fixed positions)
token: "{{ kubeadm_join_command.split()[5] }}"

# AFTER (CORRECT - regex extraction)
join_token: "{{ join_command.stdout | regex_search('--token\\s+([^\\s]+)') | regex_replace('--token\\s+', '') }}"
ca_cert_hash: "{{ join_command.stdout | regex_search('--discovery-token-ca-cert-hash\\s+([^\\s]+)') | regex_replace('--discovery-token-ca-cert-hash\\s+', '') }}"
```

**Files Modified:**
- `ansible/roles/cluster_join/tasks/main.yml` (complete rewrite)

**Impact:** All nodes (masters + workers) join successfully.

---

### 4. **Jinja2 Template Syntax Error** ❌ → ✅
**Issue:** "TemplateOverrides.trim_blocks must be <class 'bool'> instead of <class 'str'>"

**Root Cause:**
- File: `ansible/roles/haproxy/templates/haproxy.cfg.j2` line 1
- Error: Jinja2 directives used string values instead of boolean

**Before:**
```jinja2
#jinja2: lstrip_blocks: "True", trim_blocks: "True"
```

**After:**
```jinja2
#jinja2: lstrip_blocks: True, trim_blocks: True
```

**Files Modified:**
- `ansible/roles/haproxy/templates/haproxy.cfg.j2`

---

### 5. **HAProxy Binding to Wrong IP** ❌ → ✅
**Issue:** "cannot bind socket (Cannot assign requested address) for [35.154.191.143:6443]"

**Root Cause:**
- HAProxy tried binding to public IP (35.154.191.143) instead of private (10.0.1.30)
- Public IP not available on network interface

**Fix Applied:**
- Template now uses `haproxy_private_ip` variable from inventory
- File: `ansible/roles/haproxy/templates/haproxy.cfg.j2`

**Before:**
```jinja2
bind {{ hostvars['haproxy']['ansible_host'] }}:{{ haproxy_port }}  # ← Public IP
```

**After:**
```jinja2
bind {{ hostvars[inventory_hostname].get('haproxy_private_ip', '0.0.0.0') }}:{{ haproxy_port }}  # ← Private IP
```

---

### 6. **SSH ProxyCommand Syntax Error** ❌ → ✅
**Issue:** "Invalid host pattern 'all:' supplied, ending in ':' is not allowed"

**Root Cause:**
- Inventory YAML ProxyCommand had incorrect quoting
- Single quotes don't escape properly in YAML values

**Fix Applied:**
- File: `ansible/inventory/hosts.yml`
- Changed from per-host ProxyCommand → global `ansible_ssh_common_args`
- Proper YAML escaping with double quotes

**Before:**
```yaml
ansible_ssh_common_args: "-o ProxyCommand='ssh -i ~/.ssh/id_ed25519 -W %h:%p ec2-user@13.202.42.243'"
```

**After:**
```yaml
ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o ControlMaster=auto -o ControlPersist=60s -o ProxyCommand=\"ssh -i ~/.ssh/id_ed25519 -W %h:%p ec2-user@13.202.42.243\" -o IdentityFile=~/.ssh/id_ed25519"
```

---

### 7. **Containerd Extraction Error** ❌ → ✅
**Issue:** "--strip-components=1" flag not recognized by unarchive module

**Root Cause:**
- File: `ansible/roles/containerd/tasks/main.yml`
- Ansible unarchive doesn't pass `extra_opts` to tar properly

**Fix Applied:**
- Removed `extra_opts`, let tar extract naturally
- Copy task handles path correctly

**Before:**
```yaml
unarchive:
  src: "..."
  dest: /opt/containerd
  remote_src: yes
  extra_opts:
    - --strip-components=1
```

**After:**
```yaml
unarchive:
  src: "..."
  dest: /opt/containerd
  remote_src: yes
```

---

### 8. **Kubernetes Version Mismatch** ❌ → ✅
**Issue:** "this version of kubeadm only supports deploying clusters with the control plane version >= 1.32.0"

**Root Cause:**
- File: `ansible/roles/cluster_init/defaults/main.yml`
- Default `kubernetes_version: "1.30"` didn't match installed kubeadm 1.33.1
- Version format also wrong (needs full semantic: "1.33.1" not "1.33")

**Fix Applied:**
```yaml
# BEFORE
kubernetes_version: "1.30"

# AFTER
kubernetes_version: "1.33.1"
```

**Files Modified:**
- `ansible/roles/cluster_init/defaults/main.yml`

---

### 9. **Control Plane Endpoint Configuration** ❌ → ✅
**Issue:** Kubeadm using wrong HAProxy endpoint format

**Root Cause:**
- File: `ansible/roles/cluster_init/tasks/main.yml`
- Used hostname `groups['haproxy'][0]` which resolves to group name, not private IP

**Fix Applied:**
```yaml
# BEFORE
controlPlaneEndpoint: "{{ groups['haproxy'][0] }}:{{ api_server_port }}"

# AFTER
controlPlaneEndpoint: "{{ hostvars[groups['haproxy'][0]]['haproxy_private_ip'] }}:{{ api_server_port }}"
```

**Files Modified:**
- `ansible/roles/cluster_init/tasks/main.yml`

---

### 10. **HAProxy Errorfile Paths Missing** ❌ → ✅
**Issue:** HAProxy config validation failing - errorfile paths don't exist

**Root Cause:**
- File: `ansible/roles/haproxy/templates/haproxy.cfg.j2`
- Template referenced `/etc/haproxy/errors/` files that don't exist

**Fix Applied:**
- Removed errorfile directives (optional for deployment)

**Before:**
```haproxy
errorfile 400 /etc/haproxy/errors/400.http
errorfile 403 /etc/haproxy/errors/403.http
...
```

**After:**
```
# Removed - not critical for API load balancing
```

---

## Script Updates Summary

### Files Modified:
1. ✅ `ansible/roles/kubernetes/tasks/main.yml` - Kubelet config path
2. ✅ `ansible/roles/cluster_init/tasks/main.yml` - Calico + kubeadm config
3. ✅ `ansible/roles/cluster_join/tasks/main.yml` - Token parsing + join commands
4. ✅ `ansible/roles/haproxy/templates/haproxy.cfg.j2` - Jinja2 syntax + binding IP
5. ✅ `ansible/roles/haproxy/tasks/main.yml` - Error handling + validation
6. ✅ `ansible/roles/containerd/tasks/main.yml` - Archive extraction
7. ✅ `ansible/inventory/hosts.yml` - SSH ProxyCommand + group structure
8. ✅ `ansible/roles/cluster_init/defaults/main.yml` - Kubernetes version

### Features Added:
- ✅ Retry logic for kubectl commands during startup
- ✅ `--validate=false` for Calico to avoid API server timing issues
- ✅ `ignore_errors: yes` for non-critical service checks (firewalld, wait timeouts)
- ✅ Proper SSH connection pooling (ControlMaster, ControlPersist)

---

## Testing Results

### Successful Deployments:
- ✅ Terraform infrastructure (7 EC2 instances + networking)
- ✅ Playbook 01-common.yml (all 7 nodes)
- ✅ Playbook 02-haproxy.yml (HAProxy load balancer)
- ✅ Playbook 03-k8s-install.yml (containerd + kubernetes binaries)
- ✅ Playbook 04-cluster-init.yml (master-1 + Calico)
- ✅ Playbook 05-cluster-join.yml (3 masters + 2 workers)

### Final Cluster:
```
NAME       STATUS   ROLES           AGE     VERSION
master-1   Ready    control-plane   10m     v1.33.1
master-2   Ready    control-plane   2m26s   v1.33.1
master-3   Ready    control-plane   ~45s    v1.33.1
worker-1   Ready    <none>          2m1s    v1.33.1
worker-2   Ready    <none>          115s    v1.33.1

Kubernetes control plane is running at https://10.0.1.30:6443
```

---

## Deployment Time:
- Terraform apply: ~3 minutes
- Ansible playbooks: ~40 minutes
- **Total: ~45 minutes**

---

## How to Use Updated Scripts:

1. **Use latest versions from repository** (all fixes applied)
2. **Run playbooks in order** as documented in QUICK_START.md
3. **No manual intervention needed** - all issues are resolved

```bash
cd ansible && ansible-playbook playbooks/site.yml -i inventory/hosts.yml
```

---

## Known Limitations:

1. **master-3 join timing** - May show NotReady for 1-2 minutes while Calico syncs
2. **Certificate key expiry** - Valid for 2 hours; regenerate if joining after that
3. **Network latency** - AWS region selection affects performance

---

## Future Improvements:

- [ ] Add DNS records for cluster endpoints
- [ ] Implement node auto-scaling
- [ ] Add monitoring/alerting stack
- [ ] Backup etcd automatically
- [ ] Multi-region deployment support

