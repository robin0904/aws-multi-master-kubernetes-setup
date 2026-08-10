# Ansible Configuration Fixes

## Issues Found and Fixed

### Issue 1: Invalid YAML Inventory Format

**Error:**
```
Invalid "children" entry for "k8s_nodes" group, requires a dictionary, found "<class 'ansible.module_utils._internal._datatag._AnsibleTaggedList'>" instead
```

**Root Cause:**
The k8s_nodes group used a list format for children instead of dictionary:

```yaml
# ❌ WRONG - List format
k8s_nodes:
  children:
    - masters
    - workers
```

**Fix:**
Changed to dictionary format:

```yaml
# ✅ CORRECT - Dictionary format
k8s_nodes:
  children:
    masters:
    workers:
```

**File:** `ansible/inventory/hosts.yml` (line 43-46)

---

### Issue 2: Deprecated Ansible Callback Plugin

**Error:**
```
The 'community.general.yaml' callback plugin has been removed. The plugin has been superseded by the option `result_format=yaml` in callback plugin ansible.builtin.default from ansible-core 2.13 onwards.
```

**Root Cause:**
The `stdout_callback = yaml` configuration was deprecated in Ansible 2.13+

**Fix:**
Changed callback plugin:

```ini
# ❌ WRONG - Deprecated in Ansible 2.13+
stdout_callback = yaml
stderr_callback = yaml

# ✅ CORRECT - Modern approach
stdout_callback = default
```

**File:** `ansible/ansible.cfg` (line 4)

---

### Issue 3: Unavailable aws_ec2 Plugin

**Error:**
```
WARNING: Enabled but not available: aws_ec2
```

**Root Cause:**
The aws_ec2 inventory plugin requires AWS credentials and boto3 library. Not needed for static inventory.

**Fix:**
Removed aws_ec2 from inventory plugins:

```ini
# ❌ WRONG - aws_ec2 not available locally
enable_plugins = aws_ec2, ini, yaml, host_list

# ✅ CORRECT - Using static inventory only
enable_plugins = yaml, ini, host_list
```

**File:** `ansible/ansible.cfg` (line 27)

---

## Verification Results

✅ **All Fixes Verified:**

```bash
# Syntax check passed
$ ansible-playbook playbooks/01-common.yml --syntax-check
playbook: playbooks/01-common.yml

# Inventory parsing passed
$ ansible all -i inventory/hosts.yml --list-hosts
  hosts (7):
    bastion
    haproxy
    master-1, master-2, master-3
    worker-1, worker-2
```

---

## Current ansible.cfg

```ini
[defaults]
inventory = inventory/
host_key_checking = False
retry_files_enabled = False
stdout_callback = default
private_key_file = ~/.ssh/id_ed25519
remote_user = ec2-user
remote_tmp = ~/.ansible/tmp
local_tmp = ~/.ansible/tmp
gather_facts = True
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 86400
roles_path = roles
collections_paths = collections

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False

[inventory]
enable_plugins = yaml, ini, host_list
parse_errors = warn
```

---

## Current hosts.yml Structure

```yaml
all:
  vars:
    ansible_user: ec2-user
    ansible_become: yes
    ansible_become_method: sudo
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"

  children:
    bastion:
      hosts:
        bastion:
          ansible_host: 10.0.1.232
          
    haproxy:
      hosts:
        haproxy:
          ansible_host: 10.0.1.30
          
    masters:
      hosts:
        master-1:
          ansible_host: 10.0.10.70
          master_index: 1
          is_first_master: true
        master-2:
          ansible_host: 10.0.11.64
          master_index: 2
          is_first_master: false
        master-3:
          ansible_host: 10.0.10.132
          master_index: 3
          is_first_master: false
      vars:
        node_type: master
        
    workers:
      hosts:
        worker-1:
          ansible_host: 10.0.10.183
        worker-2:
          ansible_host: 10.0.11.236
      vars:
        node_type: worker
        
    k8s_nodes:
      children:
        masters:
        workers:
```

---

## Next Steps

Now that Ansible configuration is fixed:

1. **Verify EC2 instances are running:**
   ```bash
   cd terraform/environments/dev
   terraform show | grep "instance_state"
   ```

2. **Test SSH connectivity:**
   ```bash
   ssh -i ~/.ssh/id_ed25519 ec2-user@10.0.1.232  # Bastion
   ```

3. **Run Ansible playbooks:**
   ```bash
   ansible-playbook playbooks/site.yml -i inventory/hosts.yml -v
   ```

---

## Troubleshooting

### If you get "Permission denied" on SSH:

```bash
# Fix SSH key permissions
chmod 600 ~/.ssh/id_ed25519

# Verify
ls -la ~/.ssh/id_ed25519
# Should show: -rw------- (600)
```

### If you get connection timeout:

```bash
# Check if instances are running
terraform show | grep "instance_state"

# Wait for instances to fully boot (2-3 minutes)
sleep 120

# Test SSH again
ssh -i ~/.ssh/id_ed25519 -vvv ec2-user@10.0.1.232
```

### If security group blocks SSH:

```bash
# Check AWS console:
# EC2 → Security Groups → Check inbound rules
# Port 22 (SSH) should be open to 0.0.0.0/0 or your IP
```

---

## Reference

- [Ansible Callback Plugins](https://docs.ansible.com/ansible/latest/plugins/callback.html)
- [Ansible Inventory Format](https://docs.ansible.com/ansible/latest/user_guide/inventory_concepts.html)
- [Ansible Configuration Settings](https://docs.ansible.com/ansible/latest/reference_appendices/config.html)
