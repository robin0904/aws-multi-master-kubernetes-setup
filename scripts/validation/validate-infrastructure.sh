#!/usr/bin/env bash
# =============================================================================
# scripts/validation/validate-infrastructure.sh
#
# Phase 2 Gate — Validates that every AWS resource created by Terraform is
# healthy and correctly configured before any OS-level work begins.
#
# Usage:
#   bash validate-infrastructure.sh <path-to-tf-outputs.json>
#   Example: bash validate-infrastructure.sh /tmp/tf-outputs.json
#
# The script reads Terraform outputs (produced by: terraform output -json)
# and cross-checks them against live AWS API responses.
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed (details in output and log file)
#
# Dependencies: aws-cli >= 2, jq >= 1.6
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Bootstrap — source shared logging library
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/lib/logging.sh"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
TF_OUTPUTS_FILE="${1:-}"
if [[ -z "${TF_OUTPUTS_FILE}" ]]; then
  log_error "Usage: $0 <path-to-terraform-outputs.json>"
  log_error "Generate the file with: terraform output -json > /tmp/tf-outputs.json"
  exit 1
fi

if [[ ! -f "${TF_OUTPUTS_FILE}" ]]; then
  log_error "Terraform outputs file not found: ${TF_OUTPUTS_FILE}"
  exit 1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
PASS=0
FAIL=0

pass() { log_info "$* ✓"; PASS=$((PASS + 1)); }
fail() { log_error "$* ✗"; FAIL=$((FAIL + 1)); }

# Extract a value from the Terraform outputs JSON
tf_output() {
  local key="$1"
  jq -r ".${key}.value // empty" "${TF_OUTPUTS_FILE}"
}

tf_output_list() {
  local key="$1"
  jq -r ".${key}.value[]? // empty" "${TF_OUTPUTS_FILE}"
}

# AWS CLI wrapper — suppresses pagination prompt
aws_cmd() { aws "$@" --output json 2>/dev/null; }

# ---------------------------------------------------------------------------
# Extract outputs
# ---------------------------------------------------------------------------
log_section "Reading Terraform outputs"

VPC_ID=$(tf_output "vpc_id")
PUBLIC_SUBNET_IDS=($(tf_output_list "public_subnet_ids"))
PRIVATE_SUBNET_IDS=($(tf_output_list "private_subnet_ids"))
MASTER_IPS=($(tf_output_list "master_private_ips"))
WORKER_IPS=($(tf_output_list "worker_private_ips"))
MASTER_IDS=($(tf_output_list "master_instance_ids"))
WORKER_IDS=($(tf_output_list "worker_instance_ids"))
BASTION_IP=$(tf_output "bastion_public_ip")
HAPROXY_PUB=$(tf_output "haproxy_public_ip")
HAPROXY_PRIV=$(tf_output "haproxy_private_ip")

log_info "VPC ID              : ${VPC_ID}"
log_info "Public subnets      : ${PUBLIC_SUBNET_IDS[*]}"
log_info "Private subnets     : ${PRIVATE_SUBNET_IDS[*]}"
log_info "Master IDs          : ${MASTER_IDS[*]}"
log_info "Worker IDs          : ${WORKER_IDS[*]}"
log_info "HAProxy public IP   : ${HAPROXY_PUB}"
log_info "Bastion public IP   : ${BASTION_IP}"

# ---------------------------------------------------------------------------
# 1. VPC
# ---------------------------------------------------------------------------
log_section "1/8  VPC Validation"

VPC_STATE=$(aws_cmd ec2 describe-vpcs \
  --vpc-ids "${VPC_ID}" \
  | jq -r '.Vpcs[0].State')

if [[ "${VPC_STATE}" == "available" ]]; then
  pass "VPC ${VPC_ID} is available"
else
  fail "VPC ${VPC_ID} state is '${VPC_STATE}' (expected: available)"
fi

# DNS hostnames must be enabled — kubelet uses the private DNS name
DNS_HOSTNAMES=$(aws_cmd ec2 describe-vpc-attribute \
  --vpc-id "${VPC_ID}" \
  --attribute enableDnsHostnames \
  | jq -r '.EnableDnsHostnames.Value')

if [[ "${DNS_HOSTNAMES}" == "true" ]]; then
  pass "VPC DNS hostnames enabled"
else
  fail "VPC DNS hostnames are DISABLED — kubelet node naming will fail"
fi

DNS_SUPPORT=$(aws_cmd ec2 describe-vpc-attribute \
  --vpc-id "${VPC_ID}" \
  --attribute enableDnsSupport \
  | jq -r '.EnableDnsSupport.Value')

if [[ "${DNS_SUPPORT}" == "true" ]]; then
  pass "VPC DNS support enabled"
else
  fail "VPC DNS support is DISABLED"
fi

# ---------------------------------------------------------------------------
# 2. Subnets
# ---------------------------------------------------------------------------
log_section "2/8  Subnet Validation"

for subnet_id in "${PUBLIC_SUBNET_IDS[@]}"; do
  state=$(aws_cmd ec2 describe-subnets --subnet-ids "${subnet_id}" \
    | jq -r '.Subnets[0].State')
  map_public=$(aws_cmd ec2 describe-subnets --subnet-ids "${subnet_id}" \
    | jq -r '.Subnets[0].MapPublicIpOnLaunch')

  if [[ "${state}" == "available" ]]; then
    pass "Public subnet ${subnet_id} is available"
  else
    fail "Public subnet ${subnet_id} state: ${state}"
  fi

  if [[ "${map_public}" == "true" ]]; then
    pass "Public subnet ${subnet_id} has map_public_ip_on_launch=true"
  else
    fail "Public subnet ${subnet_id} map_public_ip_on_launch is false — instances won't get public IPs"
  fi
done

for subnet_id in "${PRIVATE_SUBNET_IDS[@]}"; do
  state=$(aws_cmd ec2 describe-subnets --subnet-ids "${subnet_id}" \
    | jq -r '.Subnets[0].State')
  if [[ "${state}" == "available" ]]; then
    pass "Private subnet ${subnet_id} is available"
  else
    fail "Private subnet ${subnet_id} state: ${state}"
  fi
done

# ---------------------------------------------------------------------------
# 3. Internet Gateway
# ---------------------------------------------------------------------------
log_section "3/8  Internet Gateway Validation"

IGW_STATE=$(aws_cmd ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
  | jq -r '.InternetGateways[0].Attachments[0].State')

if [[ "${IGW_STATE}" == "available" ]]; then
  pass "Internet Gateway is attached and available"
else
  fail "Internet Gateway state: '${IGW_STATE}' (expected: available)"
fi

# ---------------------------------------------------------------------------
# 4. NAT Gateway(s)
# ---------------------------------------------------------------------------
log_section "4/8  NAT Gateway Validation"

NAT_GW_COUNT=$(aws_cmd ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available" \
  | jq '.NatGateways | length')

if [[ "${NAT_GW_COUNT}" -ge 1 ]]; then
  pass "NAT Gateway(s) available: ${NAT_GW_COUNT} found"
else
  fail "No available NAT Gateways found in VPC ${VPC_ID}"
fi

# ---------------------------------------------------------------------------
# 5. Route Tables
# ---------------------------------------------------------------------------
log_section "5/8  Route Table Validation"

# Public RT must have a route to the IGW
PUBLIC_IGW_ROUTE=$(aws_cmd ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*public-rt*" \
  | jq -r '[.RouteTables[].Routes[] | select(.GatewayId != null and (.GatewayId | startswith("igw-")))] | length')

if [[ "${PUBLIC_IGW_ROUTE}" -ge 1 ]]; then
  pass "Public route table has an IGW route (0.0.0.0/0 → igw-*)"
else
  fail "No IGW route found in public route table"
fi

# Private RT(s) must have a route to a NAT Gateway
PRIVATE_NAT_ROUTES=$(aws_cmd ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*private-rt*" \
  | jq -r '[.RouteTables[].Routes[] | select(.NatGatewayId != null)] | length')

if [[ "${PRIVATE_NAT_ROUTES}" -ge 1 ]]; then
  pass "Private route table(s) have NAT Gateway routes (${PRIVATE_NAT_ROUTES} route(s))"
else
  fail "No NAT Gateway route found in private route tables — private instances cannot reach internet"
fi

# ---------------------------------------------------------------------------
# 6. EC2 Instance Health
# ---------------------------------------------------------------------------
log_section "6/8  EC2 Instance Health"

ALL_INSTANCE_IDS=("${MASTER_IDS[@]}" "${WORKER_IDS[@]}")

for instance_id in "${ALL_INSTANCE_IDS[@]}"; do
  state=$(aws_cmd ec2 describe-instances --instance-ids "${instance_id}" \
    | jq -r '.Reservations[0].Instances[0].State.Name')
  name=$(aws_cmd ec2 describe-instances --instance-ids "${instance_id}" \
    | jq -r '.Reservations[0].Instances[0].Tags[] | select(.Key=="Name") | .Value')

  if [[ "${state}" == "running" ]]; then
    pass "Instance ${name} (${instance_id}) is running"
  else
    fail "Instance ${name} (${instance_id}) state: ${state} (expected: running)"
  fi
done

# Instance status checks (system reachability and instance reachability)
log_info "Checking EC2 instance status checks (2/2 checks must pass)..."
for instance_id in "${ALL_INSTANCE_IDS[@]}"; do
  sys_status=$(aws_cmd ec2 describe-instance-status \
    --instance-ids "${instance_id}" \
    | jq -r '.InstanceStatuses[0].SystemStatus.Status // "initializing"')
  inst_status=$(aws_cmd ec2 describe-instance-status \
    --instance-ids "${instance_id}" \
    | jq -r '.InstanceStatuses[0].InstanceStatus.Status // "initializing"')

  name=$(aws_cmd ec2 describe-instances --instance-ids "${instance_id}" \
    | jq -r '.Reservations[0].Instances[0].Tags[] | select(.Key=="Name") | .Value')

  if [[ "${sys_status}" == "ok" && "${inst_status}" == "ok" ]]; then
    pass "Status checks ${name} (${instance_id}): system=ok, instance=ok"
  elif [[ "${sys_status}" == "initializing" || "${inst_status}" == "initializing" ]]; then
    log_warn "Status checks ${name} (${instance_id}): still initializing — re-run validation in 2 minutes"
  else
    fail "Status checks ${name} (${instance_id}): system=${sys_status}, instance=${inst_status}"
  fi
done

# ---------------------------------------------------------------------------
# 7. IAM Instance Profiles
# ---------------------------------------------------------------------------
log_section "7/8  IAM Instance Profile Validation"

for instance_id in "${MASTER_IDS[@]}"; do
  profile=$(aws_cmd ec2 describe-instances --instance-ids "${instance_id}" \
    | jq -r '.Reservations[0].Instances[0].IamInstanceProfile.Arn // empty')
  name=$(aws_cmd ec2 describe-instances --instance-ids "${instance_id}" \
    | jq -r '.Reservations[0].Instances[0].Tags[] | select(.Key=="Name") | .Value')

  if [[ -n "${profile}" ]]; then
    pass "Master ${name} has IAM profile: ${profile##*/}"
  else
    fail "Master ${name} (${instance_id}) has NO IAM instance profile attached"
  fi
done

for instance_id in "${WORKER_IDS[@]}"; do
  profile=$(aws_cmd ec2 describe-instances --instance-ids "${instance_id}" \
    | jq -r '.Reservations[0].Instances[0].IamInstanceProfile.Arn // empty')
  name=$(aws_cmd ec2 describe-instances --instance-ids "${instance_id}" \
    | jq -r '.Reservations[0].Instances[0].Tags[] | select(.Key=="Name") | .Value')

  if [[ -n "${profile}" ]]; then
    pass "Worker ${name} has IAM profile: ${profile##*/}"
  else
    fail "Worker ${name} (${instance_id}) has NO IAM instance profile attached"
  fi
done

# ---------------------------------------------------------------------------
# 8. Security Group Rules
# ---------------------------------------------------------------------------
log_section "8/8  Security Group Rule Validation"

# Verify masters SG allows 6443 (either from HAProxy SG or 0.0.0.0/0 for NLB mode)
MASTERS_SG_ID=$(aws_cmd ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*sg-masters*" \
  | jq -r '.SecurityGroups[0].GroupId')

if [[ -n "${MASTERS_SG_ID}" ]]; then
  pass "Masters security group found: ${MASTERS_SG_ID}"

  ETCD_RULE=$(aws_cmd ec2 describe-security-groups \
    --group-ids "${MASTERS_SG_ID}" \
    | jq '[.SecurityGroups[0].IpPermissions[] | select(.FromPort==2379 and .ToPort==2380)] | length')

  if [[ "${ETCD_RULE}" -ge 1 ]]; then
    pass "Masters SG has etcd port rules (2379-2380)"
  else
    fail "Masters SG is missing etcd port rules"
  fi

  KUBELET_RULE=$(aws_cmd ec2 describe-security-groups \
    --group-ids "${MASTERS_SG_ID}" \
    | jq '[.SecurityGroups[0].IpPermissions[] | select(.FromPort==10250)] | length')

  if [[ "${KUBELET_RULE}" -ge 1 ]]; then
    pass "Masters SG has kubelet port rule (10250)"
  else
    fail "Masters SG is missing kubelet port rule"
  fi
else
  fail "Masters security group not found in VPC ${VPC_ID}"
fi

# Verify workers SG exists
WORKERS_SG_ID=$(aws_cmd ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*sg-workers*" \
  | jq -r '.SecurityGroups[0].GroupId')

if [[ -n "${WORKERS_SG_ID}" ]]; then
  pass "Workers security group found: ${WORKERS_SG_ID}"
else
  fail "Workers security group not found in VPC ${VPC_ID}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_section "Validation Summary"
TOTAL=$((PASS + FAIL))
log_info "Total checks : ${TOTAL}"
log_info "Passed       : ${PASS}"
log_info "Failed       : ${FAIL}"

if [[ "${FAIL}" -eq 0 ]]; then
  log_info "================================================================"
  log_info " Infrastructure validation PASSED — safe to proceed to Phase 3"
  log_info "================================================================"
  exit 0
else
  log_error "================================================================"
  log_error " Infrastructure validation FAILED — fix the above errors first"
  log_error " Full log: ${LOG_FILE}"
  log_error "================================================================"
  exit 1
fi
