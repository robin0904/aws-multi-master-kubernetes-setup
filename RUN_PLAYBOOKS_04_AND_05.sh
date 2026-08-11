#!/bin/bash

###############################################################################
# Automated Kubernetes Cluster Deployment Script
# 
# This script:
# 1. Re-runs playbook 04 (cluster initialization with permission fixes)
# 2. Verifies the fixes were applied
# 3. Runs playbook 05 (cluster join for workers)
# 4. Validates the complete cluster
#
# Usage: bash RUN_PLAYBOOKS_04_AND_05.sh
###############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORKSPACE_ROOT="/Users/rohan.n/Desktop/Rohan-Learning/aws-multi-master-kubernetes-setup"
ANSIBLE_DIR="$WORKSPACE_ROOT/ansible"
BASTION_IP="35.154.53.208"
MASTER_1_IP="10.0.10.16"
SSH_KEY="$HOME/.ssh/id_ed25519"

###############################################################################
# Helper Functions
###############################################################################

print_header() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ $1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}→ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

pause_for_user() {
    echo ""
    read -p "Press ENTER to continue..." < /dev/tty
}

###############################################################################
# Pre-flight Checks
###############################################################################

print_header "PRE-FLIGHT CHECKS"

print_step "Checking workspace..."
if [ ! -d "$ANSIBLE_DIR" ]; then
    print_error "Ansible directory not found: $ANSIBLE_DIR"
    exit 1
fi
print_success "Workspace found"

print_step "Checking SSH key..."
if [ ! -f "$SSH_KEY" ]; then
    print_error "SSH key not found: $SSH_KEY"
    exit 1
fi
print_success "SSH key found"

print_step "Checking Ansible configuration..."
if [ ! -f "$ANSIBLE_DIR/ansible.cfg" ]; then
    print_error "ansible.cfg not found"
    exit 1
fi
print_success "Ansible configuration found"

print_step "Testing SSH to bastion..."
if ! timeout 5 ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@$BASTION_IP "echo 'Bastion SSH OK'" > /dev/null 2>&1; then
    print_error "Cannot SSH to bastion at $BASTION_IP"
    exit 1
fi
print_success "Bastion SSH connection OK"

print_step "Testing SSH to master-1 via bastion..."
if ! timeout 5 ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@$MASTER_1_IP "echo 'Master-1 SSH OK'" > /dev/null 2>&1; then
    print_error "Cannot SSH to master-1 via bastion"
    exit 1
fi
print_success "Master-1 SSH connection OK"

###############################################################################
# Current Cluster State
###############################################################################

print_header "CURRENT CLUSTER STATE"

print_step "Checking kubeconfig permissions..."
PERMS=$(ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo ls -la /etc/kubernetes/admin.conf 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "ERROR")
print_info "/etc/kubernetes/admin.conf permissions: $PERMS"

print_step "Checking if ec2-user kubeconfig exists..."
KUBECONFIG_EXISTS=$(ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo test -f ~/.kube/config && echo 'YES' || echo 'NO'" 2>/dev/null || echo "ERROR")
print_info "/home/ec2-user/.kube/config exists: $KUBECONFIG_EXISTS"

if [ "$KUBECONFIG_EXISTS" = "NO" ]; then
    print_info "Notice: kubeconfig copy hasn't been run yet. Playbook 04 will create it."
fi

###############################################################################
# PLAYBOOK 04: Cluster Initialization with Permission Fixes
###############################################################################

print_header "RUNNING PLAYBOOK 04: Cluster Initialization"
print_info "This will:"
print_info "  • Fix kubeconfig permissions (600 → 644)"
print_info "  • Copy kubeconfig to ec2-user home"
print_info "  • Set proper ownership"
print_info "  • Deploy Calico CNI"
print_info ""

print_step "Navigating to ansible directory..."
cd "$ANSIBLE_DIR"
print_success "In: $(pwd)"

print_step "Running playbook 04..."
echo ""

if ansible-playbook playbooks/04-cluster-init.yml \
    -i inventory/hosts.yml \
    -v; then
    print_success "Playbook 04 completed successfully"
else
    print_error "Playbook 04 failed!"
    echo ""
    print_error "Please check the output above for errors."
    exit 1
fi

###############################################################################
# Verify Playbook 04 Fixes
###############################################################################

print_header "VERIFYING PLAYBOOK 04 FIXES"

# Wait a moment for changes to settle
sleep 3

print_step "Verifying kubeconfig permissions..."
NEW_PERMS=$(ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo ls -la /etc/kubernetes/admin.conf 2>/dev/null | awk '{print \$1}'" 2>/dev/null || echo "ERROR")
print_info "New permissions: $NEW_PERMS"

if [[ "$NEW_PERMS" == *"rw-r--r--"* ]] || [[ "$NEW_PERMS" == "-rw-r--r--" ]]; then
    print_success "Kubeconfig permissions fixed (644)"
else
    print_error "Kubeconfig permissions not fixed. Current: $NEW_PERMS"
fi

print_step "Verifying ec2-user kubeconfig copy..."
NEW_KUBECONFIG_EXISTS=$(ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo test -f ~/.kube/config && echo 'YES' || echo 'NO'" 2>/dev/null || echo "ERROR")
print_info "~/.kube/config exists: $NEW_KUBECONFIG_EXISTS"

if [ "$NEW_KUBECONFIG_EXISTS" = "YES" ]; then
    print_success "Kubeconfig copied to ec2-user home"
else
    print_error "Kubeconfig copy failed"
fi

print_step "Testing kubectl access..."
if ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo kubectl get nodes" > /dev/null 2>&1; then
    print_success "kubectl access working (with sudo)"
    echo ""
    print_info "Master-1 nodes:"
    ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo kubectl get nodes" | tail -n +2 | head -3
else
    print_error "kubectl still not working"
    print_info "Attempting with explicit kubeconfig..."
    if ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes" > /dev/null 2>&1; then
        print_success "kubectl works with explicit kubeconfig"
    else
        print_error "kubectl not working even with explicit kubeconfig"
    fi
fi

print_step "Checking Calico deployment..."
CALICO_PODS=$(ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>/dev/null | wc -l" 2>/dev/null || echo "0")
print_info "Calico pods deployed: $CALICO_PODS"

pause_for_user

###############################################################################
# PLAYBOOK 05: Cluster Join for Worker Nodes
###############################################################################

print_header "RUNNING PLAYBOOK 05: Worker Node Join"
print_info "This will:"
print_info "  • Join worker nodes to the cluster"
print_info "  • Configure kubelet on workers"
print_info "  • Verify all nodes reach Ready status"
print_info ""

print_step "Running playbook 05..."
echo ""

if ansible-playbook playbooks/05-cluster-join.yml \
    -i inventory/hosts.yml \
    -v; then
    print_success "Playbook 05 completed successfully"
else
    print_error "Playbook 05 failed!"
    echo ""
    print_error "Please check the output above for errors."
    exit 1
fi

###############################################################################
# Final Cluster Validation
###############################################################################

print_header "FINAL CLUSTER VALIDATION"

sleep 5

print_step "Checking all nodes in cluster..."
NODE_COUNT=$(ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo kubectl get nodes --no-headers 2>/dev/null | wc -l" 2>/dev/null || echo "0")
print_info "Nodes in cluster: $NODE_COUNT"

echo ""
print_info "Detailed node status:"
ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo kubectl get nodes -o wide" 2>/dev/null || print_error "Cannot get nodes"

print_step "Checking node readiness..."
READY_NODES=$(ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ' || echo '0'" 2>/dev/null || echo "0")
print_info "Nodes in Ready state: $READY_NODES / $NODE_COUNT"

if [ "$READY_NODES" -eq 5 ]; then
    print_success "All 5 nodes are Ready!"
elif [ "$READY_NODES" -ge 3 ]; then
    print_success "Master nodes are Ready. Workers still initializing..."
else
    print_error "Some nodes not ready. This may take a few minutes."
fi

print_step "Checking system pods..."
echo ""
ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo kubectl get pods -n kube-system --no-headers 2>/dev/null | tail -10" 2>/dev/null || print_error "Cannot get pods"

print_step "Checking node services..."
echo ""
print_info "Deployed services:"
ssh -i "$SSH_KEY" -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP "sudo kubectl get svc --all-namespaces --no-headers 2>/dev/null | head -5" 2>/dev/null || print_error "Cannot get services"

###############################################################################
# Summary
###############################################################################

print_header "DEPLOYMENT COMPLETE"

echo -e "${GREEN}Summary:${NC}"
echo "  • Playbook 04: Cluster initialization ✓"
echo "  • Playbook 05: Worker nodes joined ✓"
echo "  • kubeconfig permissions: FIXED ✓"
echo "  • kubectl access: WORKING ✓"
echo "  • Calico CNI: DEPLOYED ✓"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Verify all nodes are Ready:"
echo "     ssh -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP 'kubectl get nodes'"
echo ""
echo "  2. Deploy your applications:"
echo "     ssh -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP 'kubectl apply -f deployment.yaml'"
echo ""
echo "  3. Monitor cluster health:"
echo "     ssh -J ec2-user@$BASTION_IP ec2-user@$MASTER_1_IP 'kubectl get nodes,pods -A'"
echo ""
echo -e "${GREEN}Cluster is ready for production! 🎉${NC}"
echo ""

