# Local Machine Setup Guide

**Question**: Where does Ansible run?  
**Answer**: On YOUR LOCAL MACHINE (same place as Terraform)

This guide shows exactly how to install everything on your local machine.

---

## Architecture Overview

```
YOUR LAPTOP/DESKTOP
├── Terraform installed
└── Ansible installed
        ↓
AWS BASTION (optional jump host)
        ↓
AWS KUBERNETES NODES (no tools needed here)
```

**Important**: 
- You run `terraform apply` on YOUR machine
- You run `ansible-playbook` on YOUR machine
- AWS EC2 nodes don't need Terraform or Ansible installed
- Ansible connects via SSH (over internet to bastion, then to private nodes)

---

## Step 1: Install Terraform

### macOS (Homebrew)

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify
terraform --version
# Should show: Terraform v1.6.0 (or higher)
```

### Ubuntu/Debian

```bash
# Add HashiCorp repository
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

# Install
sudo apt-get update
sudo apt-get install terraform

# Verify
terraform --version
```

### RHEL/CentOS/Rocky

```bash
# Add HashiCorp repository
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo

# Install
sudo yum install terraform

# Verify
terraform --version
```

### Windows (WSL2 recommended)

Install WSL2 first, then follow Ubuntu steps in WSL terminal.

---

## Step 2: Install Ansible

### macOS

```bash
# Option 1: Homebrew
brew install ansible

# Option 2: pip (recommended, more up-to-date)
python3 -m pip install --upgrade pip
pip3 install ansible

# Verify
ansible --version
# Should show: ansible [core 2.12.x] (or higher)
```

### Ubuntu/Debian

```bash
# Install Python first
sudo apt-get update
sudo apt-get install -y python3 python3-pip

# Install Ansible
pip3 install --upgrade pip
pip3 install ansible

# Verify
ansible --version
```

### RHEL/CentOS/Rocky

```bash
# Install Python first
sudo yum install -y python3 python3-pip

# Install Ansible
pip3 install --upgrade pip
pip3 install ansible

# Verify
ansible --version
```

### Windows

Install WSL2, then follow Ubuntu steps in WSL terminal.

---

## Step 3: Install AWS CLI

### macOS

```bash
brew install awscli

# Verify
aws --version
```

### Ubuntu/Debian

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify
aws --version
```

### RHEL/CentOS/Rocky

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify
aws --version
```

---

## Step 4: Install jq (JSON processor)

### macOS

```bash
brew install jq

# Verify
jq --version
```

### Ubuntu/Debian

```bash
sudo apt-get install jq

# Verify
jq --version
```

### RHEL/CentOS/Rocky

```bash
sudo yum install jq

# Verify
jq --version
```

---

## Step 5: Install kubectl (for verification only)

### macOS

```bash
brew install kubectl

# Verify
kubectl version --client
```

### Ubuntu/Debian

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify
kubectl version --client
```

### RHEL/CentOS/Rocky

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify
kubectl version --client
```

---

## Step 6: Configure AWS Credentials

### Get AWS Access Key

1. Go to AWS IAM console
2. Create IAM user with `AdministratorAccess` policy (or minimum required)
3. Create access key pair (access_key_id + secret_access_key)

### Configure Local Machine

```bash
# Option 1: Interactive setup (recommended)
aws configure

# Then enter:
# AWS Access Key ID: [your-access-key-id]
# AWS Secret Access Key: [your-secret-access-key]
# Default region name: ap-south-1
# Default output format: json

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="ap-south-1"

# Option 3: Edit ~/.aws/credentials directly
cat ~/.aws/credentials
# Should show:
# [default]
# aws_access_key_id = xxx
# aws_secret_access_key = yyy
```

### Verify AWS Configuration

```bash
aws sts get-caller-identity

# Should show:
# {
#   "UserId": "AIDAI...",
#   "Account": "123456789012",
#   "Arn": "arn:aws:iam::123456789012:user/your-username"
# }
```

---

## Step 7: Generate SSH Key Pair

```bash
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Verify
ls -la ~/.ssh/id_ed25519*
# Should show:
# -rw-------  id_ed25519
# -rw-r--r--  id_ed25519.pub

# Check permissions (must be 600)
chmod 600 ~/.ssh/id_ed25519
```

**Why ed25519?**
- Smaller key size
- Better security
- Widely supported

---

## Step 8: Verify All Tools

```bash
# Create verification script
cat > /tmp/verify-tools.sh << 'EOF'
#!/bin/bash

echo "=== Checking Tools Installation ==="
echo ""

echo "✓ Terraform:"
terraform --version || echo "❌ NOT INSTALLED"

echo ""
echo "✓ Ansible:"
ansible --version || echo "❌ NOT INSTALLED"

echo ""
echo "✓ AWS CLI:"
aws --version || echo "❌ NOT INSTALLED"

echo ""
echo "✓ jq:"
jq --version || echo "❌ NOT INSTALLED"

echo ""
echo "✓ kubectl:"
kubectl version --client 2>/dev/null || echo "⚠️  NOT INSTALLED (optional)"

echo ""
echo "=== Checking AWS Configuration ==="
aws sts get-caller-identity 2>/dev/null || echo "❌ AWS credentials not configured"

echo ""
echo "=== Checking SSH Key ==="
if [ -f ~/.ssh/id_ed25519 ]; then
    echo "✓ SSH key exists"
    chmod 600 ~/.ssh/id_ed25519
else
    echo "❌ SSH key not found at ~/.ssh/id_ed25519"
fi

echo ""
echo "=== All Checks Complete ==="
EOF

bash /tmp/verify-tools.sh
```

---

## Step 9: Test Terraform

```bash
cd /path/to/project/terraform/environments/dev

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Should show: "Success! The configuration is valid."
```

---

## Step 10: Test Ansible

```bash
cd /path/to/project/ansible

# Install Ansible dependencies
ansible-galaxy install -r requirements.yml

# Check syntax (no actual execution)
ansible-playbook playbooks/site.yml --syntax-check

# Should show: "playbook: playbooks/site.yml"
```

---

## Troubleshooting Local Setup

### Terraform Not Found

```bash
# Add to PATH
export PATH="$PATH:/usr/local/bin"

# Or reinstall
brew install terraform  # macOS
apt-get install terraform  # Ubuntu
```

### Ansible Not Found

```bash
# Check Python
python3 --version

# Reinstall Ansible
pip3 install --upgrade ansible

# Add to PATH if needed
export PATH="$PATH:$HOME/.local/bin"
```

### AWS Credentials Not Working

```bash
# Verify configuration
cat ~/.aws/credentials

# Test connection
aws sts get-caller-identity

# If failing, reconfigure
aws configure
```

### SSH Key Permissions

```bash
# Must be 600
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub

# Verify
ls -la ~/.ssh/id_ed25519*
# Should show:
# -rw-------  id_ed25519
# -rw-r--r--  id_ed25519.pub
```

---

## What's Installed Where?

```
Your Local Machine
│
├── Terraform binary
│   └── /usr/local/bin/terraform (macOS)
│   └── /usr/bin/terraform (Linux)
│
├── Ansible
│   └── /usr/local/bin/ansible (macOS)
│   └── ~/.local/bin/ansible (Linux via pip)
│
├── AWS CLI
│   └── /usr/local/bin/aws
│
├── SSH Key
│   └── ~/.ssh/id_ed25519 (PRIVATE KEY - never share)
│   └── ~/.ssh/id_ed25519.pub (PUBLIC KEY - can share)
│
├── AWS Credentials
│   └── ~/.aws/credentials (local file - keep secret)
│   └── ~/.aws/config (local file)
│
└── Project Files
    └── ~/aws-multi-master-kubernetes-setup/
        ├── terraform/
        ├── ansible/
        └── docs/
```

---

## How Ansible Connects to AWS Nodes

```
1. You run on local machine:
   ansible-playbook playbooks/site.yml -i inventory/hosts.yml

2. Ansible reads hosts.yml:
   - master-1: 10.0.10.10
   - worker-1: 10.0.11.10
   etc.

3. Ansible connects via SSH:
   - Uses ~/.ssh/id_ed25519 (private key)
   - Connects as ec2-user (default AWS Linux user)
   - Uses bastion as jump host if needed
   
4. On each node:
   - Runs tasks (install packages, configure services)
   - Uses sudo/become for root access
   
5. Output comes back to your machine
   - You see all logs in real-time
   - Can ctrl+c to stop anytime
```

---

## Quick Reference: Commands from Local Machine

```bash
# Provision infrastructure
cd terraform/environments/dev
terraform apply

# Generate Ansible inventory
cd ../../ansible/inventory
bash generate-inventory.sh

# Run playbooks
cd ..
ansible-playbook playbooks/01-common.yml -i inventory/hosts.yml

# View cluster
kubectl get nodes

# SSH to bastion (if enabled)
ssh -i ~/.ssh/id_ed25519 ec2-user@<bastion-public-ip>

# SSH to internal node (via bastion)
ssh -i ~/.ssh/id_ed25519 -J ec2-user@<bastion-public-ip> ec2-user@10.0.10.10
```

---

## One-Liner Complete Setup (macOS)

```bash
brew install terraform ansible awscli jq kubectl && \
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" && \
aws configure && \
echo "✅ Setup complete!"
```

---

## Next Steps

1. ✅ Install all tools (this guide)
2. ✅ Configure AWS credentials
3. ✅ Generate SSH key
4. → Go to [QUICK_START.md](../QUICK_START.md)
5. → Follow Terraform + Ansible deployment

---

## Support

If something doesn't work:
1. Check tool version: `terraform --version`, `ansible --version`
2. Check AWS credentials: `aws sts get-caller-identity`
3. Check SSH key: `ls -la ~/.ssh/id_ed25519*`
4. See [docs/EXECUTION_GUIDE.md](./EXECUTION_GUIDE.md) troubleshooting section
