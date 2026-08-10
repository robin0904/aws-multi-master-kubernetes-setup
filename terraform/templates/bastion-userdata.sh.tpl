#!/usr/bin/env bash
# =============================================================================
# bastion-userdata.sh.tpl
# User-data script for the Bastion host.
# Template variables injected by Terraform ec2 module.
#
# Variables:
#   hostname    — desired hostname for this instance
#   environment — deployment environment (dev/qa/prod)
# =============================================================================
set -euo pipefail

# ---- Set hostname ----
hostnamectl set-hostname "${hostname}"
echo "127.0.0.1 ${hostname}" >> /etc/hosts

# ---- System update ----
dnf update -y --quiet

# ---- Install useful admin tools ----
dnf install -y \
  bash-completion \
  bind-utils \
  curl \
  git \
  htop \
  jq \
  nc \
  net-tools \
  tcpdump \
  telnet \
  vim \
  wget

# ---- Configure SSH for agent forwarding ----
# Allows operators to hop from bastion to private nodes using their local keys.
cat >> /etc/ssh/sshd_config <<'SSHD'
AllowAgentForwarding yes
AllowTcpForwarding yes
SSHD
systemctl restart sshd

# ---- Write environment tag to instance ----
echo "ENVIRONMENT=${environment}" >> /etc/environment

# ---- Signal successful completion ----
echo "Bastion user-data completed at $(date)" >> /var/log/userdata.log
