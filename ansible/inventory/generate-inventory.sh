#!/bin/bash
# =============================================================================
# ansible/inventory/generate-inventory.sh
# Generate static inventory from Terraform outputs
#
# This script creates an Ansible inventory with:
# - Bastion: PUBLIC IP for SSH access from local machine
# - HAProxy, Masters, Workers: PRIVATE IPs (internal VPC communication)
# - ProxyCommand: Routes all private node access through Bastion's public IP
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

# Extract PUBLIC and PRIVATE IPs for Bastion
BASTION_PUBLIC_IP=$(jq -r '.bastion_public_ip.value' "$TF_OUTPUTS" 2>/dev/null || echo "")
BASTION_PRIVATE_IP=$(jq -r '.bastion_private_ip.value' "$TF_OUTPUTS")

# If no public IP in outputs, use private (fallback)
if [ -z "$BASTION_PUBLIC_IP" ] || [ "$BASTION_PUBLIC_IP" = "null" ]; then
    BASTION_PUBLIC_IP="$BASTION_PRIVATE_IP"
    echo "⚠ WARNING: No bastion_public_ip in terraform outputs, using private IP: $BASTION_PRIVATE_IP"
else
    echo "✓ Bastion Public IP: $BASTION_PUBLIC_IP"
fi

HAPROXY_IP=$(jq -r '.haproxy_private_ip.value' "$TF_OUTPUTS")
MASTER_IPS=($(jq -r '.master_private_ips.value[]' "$TF_OUTPUTS"))
WORKER_IPS=($(jq -r '.worker_private_ips.value[]' "$TF_OUTPUTS"))

echo "✓ Bastion Private IP: $BASTION_PRIVATE_IP"
echo "✓ HAProxy: $HAPROXY_IP"
echo "✓ Masters: ${MASTER_IPS[@]}"
echo "✓ Workers: ${WORKER_IPS[@]}"

# Generate hosts.yml with proper SSH routing (simplified ProxyCommand)
cat > "$OUTPUT_FILE" << EOF
# Generated from terraform outputs — $(date)
all:
  vars:
    ansible_user: ec2-user
    ansible_become: yes
    ansible_become_method: sudo
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
    bastion_host: $BASTION_PUBLIC_IP

  children:
    bastion:
      hosts:
        bastion:
          ansible_host: $BASTION_PUBLIC_IP
          
    haproxy:
      hosts:
        haproxy:
          ansible_host: $HAPROXY_IP
          haproxy_private_ip: $HAPROXY_IP
          ansible_ssh_extra_args: "-o ProxyCommand='ssh -o StrictHostKeyChecking=no -W %h:%p ec2-user@$BASTION_PUBLIC_IP'"
          
    masters:
      hosts:
EOF

# Add masters with ProxyCommand
for i in "${!MASTER_IPS[@]}"; do
    idx=$((i + 1))
    first_master=$([ $i -eq 0 ] && echo "true" || echo "false")
    cat >> "$OUTPUT_FILE" << EOF
        master-$idx:
          ansible_host: ${MASTER_IPS[$i]}
          master_index: $idx
          is_first_master: $first_master
          ansible_ssh_extra_args: "-o ProxyCommand='ssh -o StrictHostKeyChecking=no -W %h:%p ec2-user@$BASTION_PUBLIC_IP'"
EOF
done

cat >> "$OUTPUT_FILE" << EOF
      vars:
        node_type: master
        
    workers:
      hosts:
EOF

# Add workers with ProxyCommand
for i in "${!WORKER_IPS[@]}"; do
    idx=$((i + 1))
    cat >> "$OUTPUT_FILE" << EOF
        worker-$idx:
          ansible_host: ${WORKER_IPS[$i]}
          ansible_ssh_extra_args: "-o ProxyCommand='ssh -o StrictHostKeyChecking=no -W %h:%p ec2-user@$BASTION_PUBLIC_IP'"
EOF
done

cat >> "$OUTPUT_FILE" << EOF
      vars:
        node_type: worker
        
    k8s_nodes:
      children:
        masters: {}
        workers: {}
      vars:
        haproxy_private_ip: $HAPROXY_IP
        api_server_port: 6443
        pod_cidr: 192.168.0.0/16
        service_cidr: 10.96.0.0/12
        kubernetes_version: 1.33.1
        calico_version: v3.29.1
        bootstrap_token: "123456.1234567890abcdef"
EOF

echo ""
echo "✓ Generated $OUTPUT_FILE"
echo ""
echo "=== Inventory Configuration ==="
echo "Bastion SSH Entry Point: $BASTION_PUBLIC_IP"
echo "Internal HAProxy: $HAPROXY_IP"
echo "Kubernetes API: $HAPROXY_IP:6443 (via HAProxy)"
echo ""
echo "Next steps:"
echo "  1. Run playbooks: cd .. && ansible-playbook playbooks/01-common.yml -i inventory/hosts.yml -v"
echo ""


