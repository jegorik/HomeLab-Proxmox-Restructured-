#!/usr/bin/env bash
# =============================================================================
# Common Functions and Variables for LXC SemaphoreUI
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Logging functions
log_info()    { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE:-/dev/null}"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE:-/dev/null}"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE:-/dev/null}"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE:-/dev/null}"; }

log_header() {
    echo -e "\n${BOLD}${CYAN}========================================${NC}" | tee -a "${LOG_FILE:-/dev/null}"
    echo -e "${BOLD}${CYAN}$1${NC}" | tee -a "${LOG_FILE:-/dev/null}"
    echo -e "${BOLD}${CYAN}========================================${NC}\n" | tee -a "${LOG_FILE:-/dev/null}"
}

# User confirmation
confirm() {
    local prompt="$1"
    while true; do
        echo -e -n "${YELLOW}${prompt} (yes/no): ${NC}"
        read -r response
        case "${response}" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo -e "${RED}Please answer 'yes' or 'no'${NC}" ;;
        esac
    done
}

# Check if command exists
check_command() {
    local cmd="$1"
    local hint="${2:-}"
    
    if command -v "${cmd}" &>/dev/null; then
        log_success "Found: ${cmd}"
        return 0
    else
        log_error "Missing: ${cmd}"
        [[ -n "${hint}" ]] && log_info "Install: ${hint}"
        return 1
    fi
}

# Wait for port to be open
wait_for_port() {
    local host=$1
    local port=$2
    local timeout=${3:-60}

    log_info "Waiting for ${host}:${port}..."

    # Use python to check connection
    local python_cmd="import socket, sys; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.settimeout(1); result = s.connect_ex(('$host', $port)); sys.exit(result)"

    local start_ts
    start_ts=$(date +%s)
    while true; do
        if python3 -c "$python_cmd" 2>/dev/null; then
             log_success "Port ${port} is open"
             return 0
        fi

        if [[ $(( $(date +%s) - start_ts )) -gt $timeout ]]; then
            log_error "Timeout waiting for ${host}:${port}"
            return 1
        fi
        sleep 1
    done
}

# Get IaC tool (tofu or terraform)
get_iac_tool() {
    if command -v tofu &>/dev/null; then
        echo "tofu"
    elif command -v terraform &>/dev/null; then
        echo "terraform"
    else
        log_error "Neither OpenTofu nor Terraform found"
        return 1
    fi
}
