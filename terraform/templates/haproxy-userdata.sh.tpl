#!/usr/bin/env bash
# =============================================================================
# haproxy-userdata.sh.tpl  —  HAProxy EC2 instance bootstrap
#
# Injected template variables:
#   hostname      — e.g. dev-k8s-cluster-haproxy
#   environment   — dev / qa / prod
#   cluster_name  — used as SSM path prefix
#   aws_region    — AWS region
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/userdata.log | logger -t userdata -s 2>/dev/console) 2>&1

echo "=== HAProxy user-data started: $(date) ==="

# ---- Hostname ----
hostnamectl set-hostname "${hostname}"
echo "127.0.0.1 ${hostname}" >> /etc/hosts
echo "ENVIRONMENT=${environment}" >> /etc/environment

# ---- System update + install ----
dnf update -y --quiet
dnf install -y haproxy jq curl net-tools bind-utils aws-cli

# ---- Helper: SSM polling ----
SSM_PATH="/${cluster_name}"
REGION="${aws_region}"

ssm_get() {
  aws ssm get-parameter \
    --region "${REGION}" \
    --name "$1" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text 2>/dev/null || echo ""
}

# ---- Wait for HAProxy config to appear in SSM ----
# Terraform writes /${cluster_name}/config/haproxy_cfg before EC2 launches,
# so this should be available almost immediately.
echo "Waiting for haproxy config in SSM..."
RETRIES=0
until CFG=$(ssm_get "$${SSM_PATH}/config/haproxy_cfg") && [[ -n "${CFG:-}" ]]; do
  RETRIES=$((RETRIES+1))
  [[ "${RETRIES}" -ge 30 ]] && { echo "ERROR: haproxy config not found in SSM after 5 min"; exit 1; }
  sleep 10
done

# ---- Write and validate config ----
echo "$${CFG}" > /etc/haproxy/haproxy.cfg
haproxy -c -f /etc/haproxy/haproxy.cfg || { echo "ERROR: haproxy config invalid"; exit 1; }
echo "HAProxy config written and validated"

# ---- Start HAProxy ----
systemctl enable haproxy
systemctl start haproxy
sleep 3

if ! systemctl is-active --quiet haproxy; then
  echo "ERROR: HAProxy failed to start"
  systemctl status haproxy --no-pager || true
  exit 1
fi
echo "HAProxy is running on port 6443"

# ---- Signal ready to SSM ----
aws ssm put-parameter \
  --region "${REGION}" \
  --name "$${SSM_PATH}/bootstrap/haproxy_status" \
  --value "READY" \
  --type String \
  --overwrite
echo "SSM haproxy_status set to READY"

echo "=== HAProxy user-data completed: $(date) ==="
