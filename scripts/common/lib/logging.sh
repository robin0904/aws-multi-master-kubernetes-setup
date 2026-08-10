#!/usr/bin/env bash
# =============================================================================
# scripts/common/lib/logging.sh
#
# Shared logging library sourced by all install scripts.
# Provides timestamped, levelled log output to both stdout and a log file.
#
# Usage:
#   source "$(dirname "$0")/../../common/lib/logging.sh"
#   log_info  "Starting OS preparation..."
#   log_warn  "swap already disabled, skipping"
#   log_error "Package installation failed"
#   log_debug "Running: apt-get install -y curl"  # only if VERBOSE=true
# =============================================================================

# Ensure LOG_DIR and LOG_FILE are set (fall back to sensible defaults if
# config.env has not been sourced yet)
LOG_DIR="${LOG_DIR:-/var/log/k8s-install}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/install.log}"
VERBOSE="${VERBOSE:-false}"

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Colour codes (disabled if stdout is not a terminal)
if [[ -t 1 ]]; then
  _RESET='\033[0m'
  _RED='\033[0;31m'
  _YELLOW='\033[1;33m'
  _GREEN='\033[0;32m'
  _CYAN='\033[0;36m'
else
  _RESET=''
  _RED=''
  _YELLOW=''
  _GREEN=''
  _CYAN=''
fi

# Internal helper — formats and writes a log entry
_log() {
  local level="$1"
  local colour="$2"
  local message="$3"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local line="[${timestamp}] [${level}]  ${message}"

  # Write to stdout with colour
  echo -e "${colour}${line}${_RESET}"

  # Write to log file (no colour codes)
  echo "${line}" >> "${LOG_FILE}"
}

log_info()  { _log "INFO " "${_GREEN}"  "$*"; }
log_warn()  { _log "WARN " "${_YELLOW}" "$*"; }
log_error() { _log "ERROR" "${_RED}"    "$*"; }
log_debug() {
  if [[ "${VERBOSE}" == "true" ]]; then
    _log "DEBUG" "${_CYAN}" "$*"
  fi
}

# Log a section header — useful for separating major phases in long scripts
log_section() {
  local message="$*"
  local line
  line="$(printf '=%.0s' {1..60})"
  log_info "${line}"
  log_info " ${message}"
  log_info "${line}"
}

# Called by the ERR trap to log the failing line number
log_trap_error() {
  local exit_code=$?
  local line_number="${1:-unknown}"
  log_error "Script failed at line ${line_number} with exit code ${exit_code}"
  log_error "Check ${LOG_FILE} for full output"
  exit "${exit_code}"
}
