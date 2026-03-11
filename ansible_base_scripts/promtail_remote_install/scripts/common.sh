#!/usr/bin/env bash
# =============================================================================
# Common Functions - Promtail Remote Install
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# Color codes — only emit ANSI sequences when writing to an interactive terminal
if [[ -t 1 && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

# log_info writes an "[INFO]" message to stdout (rendered in blue when colors are enabled) and appends the message to LOG_FILE (defaults to /dev/null).
log_info()    { echo -e "${BLUE}[INFO]${NC} ${1}"    | tee -a "${LOG_FILE:-/dev/null}"; }
# log_success writes a SUCCESS-level message prefixed with `[SUCCESS]` to stdout (colorized when color variables are set) and appends it to LOG_FILE (defaults to /dev/null).
log_success() { echo -e "${GREEN}[SUCCESS]${NC} ${1}" | tee -a "${LOG_FILE:-/dev/null}"; }
# log_warning prints a WARNING-prefixed message to stdout and appends the same output to LOG_FILE (defaults to /dev/null), using the YELLOW/NC color codes when they are defined.
log_warning() { echo -e "${YELLOW}[WARNING]${NC} ${1}" | tee -a "${LOG_FILE:-/dev/null}"; }
# log_error writes an ERROR-level message prefixed with "[ERROR]" to stdout (colorized when supported) and appends it to LOG_FILE (default /dev/null).
log_error()   { echo -e "${RED}[ERROR]${NC} ${1}"    | tee -a "${LOG_FILE:-/dev/null}"; }

# log_header renders a formatted header block using its first argument as the title, writes the header to stdout and appends it to LOG_FILE (defaults to /dev/null).
log_header() {
    echo -e "\n${BOLD}${CYAN}========================================${NC}" | tee -a "${LOG_FILE:-/dev/null}"
    echo -e "${BOLD}${CYAN}$1${NC}"                                         | tee -a "${LOG_FILE:-/dev/null}"
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
            [Nn]|[Nn][Oo])     return 1 ;;
            *) echo -e "${RED}Please answer 'yes' or 'no'${NC}" ;;
        esac
    done
}

# Check if a command exists
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
