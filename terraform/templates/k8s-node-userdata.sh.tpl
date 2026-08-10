#!/usr/bin/env bash
# =============================================================================
# k8s-node-userdata.sh.tpl
# Minimal user-data for Kubernetes master and worker nodes.
# Sets hostname and installs prerequisite packages only.
# Full OS prep, runtime, and Kubernetes installation are handled by the
# Bash scripts in scripts/common/ (run after infrastructure is validated).
#
# Variables:
#   hostname    — desired hostname for this instance
#   environment — deployment environment (dev/qa/prod)
#   node_role   — "master" or "worker"
# =============================================================================
set -euo pipefail

# ---- Set hostname ----
# Kubernetes uses the hostname as the node name by default.
hostnamectl set-hostname "${hostname}"
echo "127.0.0.1 ${hostname}" >> /etc/hosts

# ---- Write node role and environment to /etc/environment ----
# This is sourced by the Bash install scripts for conditional logic.
echo "ENVIRONMENT=${environment}" >> /etc/environment
echo "NODE_ROLE=${node_role}"     >> /etc/environment

# ---- System update ----
# Do minimal updates here; the full OS prep script does the rest.
dnf update -y --quiet

# ---- Install baseline packages needed for health checks and scripting ----
dnf install -y \
  bash-completion \
  bind-utils \
  curl \
  jq \
  net-tools \
  vim \
  wget

echo "Node user-data for ${hostname} (${node_role}) completed at $(date)" >> /var/log/userdata.log
