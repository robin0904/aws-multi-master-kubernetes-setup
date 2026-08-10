#!/bin/bash
# =============================================================================
# ansible/inventory/generate-inventory.sh
# Generate static inventory from Terraform outputs
#
# Usage:
#   cd terraform/environments/dev
#   terraform output -json > ../../ansible/inventory/tf_outputs.json
#   cd ../../ansible/inventory
#   bash generate-inventory.sh
# =============================================================================

set -e

TF_OUTPUTS="${1:-tf_outputs.json}"
OUTPUT_FILE="hosts.yml"

if [ ! -f "$TF_OUTPUTS" ]; then
    echo "ERROR: $TF_OUTPUTS not found"
    echo "Run: terraform output -json > ../../ansible/inventory/tf_outputs.json"
    exit 1
fi

echo "=== Generating Ansible inventory from $TF_OUTPUTS ==="

# Extract values from terraform outputs
BASTION_IP=$(jq -r '.bastion_private_ip.value' "$TF_OUTPUTS")
HAPROXY_IP=$(jq -r '.haproxy_private_ip.value' "$TF_OUTPUTS")
MASTER_IPS=($(jq -r '.master_private_ips.value[]' "$TF_OUTPUTS"))
WORKER_IPS=($(jq -r '.worker_private_ips.value[]' "$TF_OUTPUTS"))

echo "Bastion: $BASTION_IP"
echo "HAProxy: $HAPROXY_IP"
echo "Masters: ${MASTER_IPS[@]}"
echo "Workers: ${WORKER_IPS[@]}"

# Generate hosts.yml
cat > "$OUTPUT_FILE" << EOF
# Generated from terraform outputs — $(date)
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
          ansible_host: $BASTION_IP
          
    haproxy:
      hosts:
        haproxy:
          ansible_host: $HAPROXY_IP
          
    masters:
      hosts:
EOF

# Add masters
for i in "${!MASTER_IPS[@]}"; do
    idx=$((i + 1))
    first_master=$([ $i -eq 0 ] && echo "true" || echo "false")
    cat >> "$OUTPUT_FILE" << EOF
        master-$idx:
          ansible_host: ${MASTER_IPS[$i]}
          master_index: $idx
          is_first_master: $first_master
EOF
done

cat >> "$OUTPUT_FILE" << EOF
      vars:
        node_type: master
        
    workers:
      hosts:
EOF

# Add workers
for i in "${!WORKER_IPS[@]}"; do
    idx=$((i + 1))
    cat >> "$OUTPUT_FILE" << EOF
        worker-$idx:
          ansible_host: ${WORKER_IPS[$i]}
EOF
done

cat >> "$OUTPUT_FILE" << EOF
      vars:
        node_type: worker
        
    k8s_nodes:
      children:
        - masters
        - workers
EOF

echo "✓ Generated $OUTPUT_FILE"
echo "✓ Next: ansible-playbook playbooks/site.yml -i inventory/hosts.yml"
