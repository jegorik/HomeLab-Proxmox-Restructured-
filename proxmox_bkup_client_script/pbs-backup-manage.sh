#!/usr/bin/env bash
# =============================================================================
# pbs-backup-manage.sh — PBS Backup Profile Management Tool
# =============================================================================
#
# Interactive management CLI for PBS backup profiles. Handles installation
# of configs, systemd units, connection testing, and manual backup execution.
#
# Usage:
#   pbs-backup-manage.sh <command> [profile]
#
# Commands:
#   install  <profile>  - Install a profile (config → systemd units → enable timer)
#   remove   <profile>  - Remove a profile and its systemd units
#   status   [profile]  - Show status of one or all profiles
#   test     <profile>  - Test PBS server connectivity
#   run      <profile>  - Execute an immediate manual backup
#   validate <profile>  - Validate config files without running
#   list                - List all configured profiles
#   logs     <profile>  - Show recent backup logs
#   help                - Show this help message
#
# Exit Codes:
#   0 - Success
#   1 - General error
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly SCRIPT_VERSION="1.0.0"
readonly CONFIG_DIR="/etc/pbs-backup"
readonly LOG_DIR="/var/log/pbs-backup"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly SCRIPT_INSTALL_PATH="/usr/local/bin/pbs-backup.sh"

# Path to the backup runner script (co-located with this management script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly BACKUP_SCRIPT="${SCRIPT_DIR}/pbs-backup.sh"

# Colors for terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

# Print formatted informational message
info()  { printf "${BLUE}[INFO]${NC}  %s\n" "$1"; }
# Print formatted success message
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$1"; }
# Print formatted warning message
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$1"; }
# Print formatted error message to stderr
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

# check_root - Ensure the script is running as root.
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# check_pbs_client - Verify proxmox-backup-client is installed.
check_pbs_client() {
    if ! command -v proxmox-backup-client &>/dev/null; then
        error "proxmox-backup-client is not installed"
        info "Install it first:"
        echo "  apt install proxmox-backup-client    (Debian/Proxmox)"
        exit 1
    fi
}

# validate_profile_name - Ensure profile name contains only safe characters.
# Arguments: $1 - profile name
validate_profile_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        error "Profile name cannot be empty"
        return 1
    fi
    if ! [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        error "Profile name contains invalid characters: '$name'"
        error "Allowed: letters, numbers, dash, underscore, dot (must start with alphanumeric)"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Config file safe parser (matches pbs-backup.sh logic)
# ---------------------------------------------------------------------------

# parse_config_file - Parse key=value config without sourcing.
# Arguments: $1 - file path
# Sets global variables for the parsed keys.
parse_config_file() {
    local config_file="$1"
    local line key value

    # Initialize defaults
    PBS_SERVER="" PBS_PORT="8007" PBS_DATASTORE="" PBS_AUTH_ID=""
    PBS_FINGERPRINT="" PBS_PASSWORD=""
    BACKUP_PATHS="" EXCLUDE_PATTERNS="" BACKUP_SCHEDULE="*-*-* 02:00:00"
    KEEP_LAST=3 KEEP_DAILY=7 KEEP_WEEKLY=4 KEEP_MONTHLY=3
    CHANGE_DETECTION_MODE="metadata" SKIP_LOST_AND_FOUND="true"
    VERBOSE="false" LOCK_TIMEOUT=300 NOTIFY_ON_FAILURE=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        if [[ "$line" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*([^[:space:]#]*) ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        case "$key" in
            PBS_SERVER)              PBS_SERVER="$value" ;;
            PBS_PORT)                PBS_PORT="$value" ;;
            PBS_DATASTORE)           PBS_DATASTORE="$value" ;;
            PBS_AUTH_ID)             PBS_AUTH_ID="$value" ;;
            PBS_FINGERPRINT)         PBS_FINGERPRINT="$value" ;;
            PBS_PASSWORD)            PBS_PASSWORD="$value" ;;
            BACKUP_PATHS)            BACKUP_PATHS="$value" ;;
            EXCLUDE_PATTERNS)        EXCLUDE_PATTERNS="$value" ;;
            BACKUP_SCHEDULE)         BACKUP_SCHEDULE="$value" ;;
            KEEP_LAST)               KEEP_LAST="$value" ;;
            KEEP_DAILY)              KEEP_DAILY="$value" ;;
            KEEP_WEEKLY)             KEEP_WEEKLY="$value" ;;
            KEEP_MONTHLY)            KEEP_MONTHLY="$value" ;;
            CHANGE_DETECTION_MODE)   CHANGE_DETECTION_MODE="$value" ;;
            SKIP_LOST_AND_FOUND)     SKIP_LOST_AND_FOUND="$value" ;;
            VERBOSE)                 VERBOSE="$value" ;;
            LOCK_TIMEOUT)            LOCK_TIMEOUT="$value" ;;
            NOTIFY_ON_FAILURE)       NOTIFY_ON_FAILURE="$value" ;;
            *) ;;
        esac
    done < "$config_file"
}

# ---------------------------------------------------------------------------
# Profile operations
# ---------------------------------------------------------------------------

# profile_exists - Check if a profile has config files installed.
# Arguments: $1 - profile name
# Returns:   0 if exists, 1 otherwise
profile_exists() {
    [[ -f "${CONFIG_DIR}/$1.conf" ]]
}

# list_profiles - List all installed backup profiles.
cmd_list() {
    echo
    printf "${BOLD}═══════════════════════════════════════════${NC}\n"
    printf "${BOLD}  PBS Backup Profiles${NC}\n"
    printf "${BOLD}═══════════════════════════════════════════${NC}\n"
    echo

    if [[ ! -d "$CONFIG_DIR" ]] || ! ls "${CONFIG_DIR}"/*.conf &>/dev/null; then
        warn "No backup profiles configured"
        info "Create one with: $0 install <profile-name>"
        return 0
    fi

    local count=0
    for conf in "${CONFIG_DIR}"/*.conf; do
        [[ ! -f "$conf" ]] && continue
        local profile
        profile="$(basename "$conf" .conf)"
        count=$((count + 1))

        # Parse config for display
        parse_config_file "$conf"

        # Check timer status
        local timer_status="${RED}disabled${NC}"
        if systemctl is-active "pbs-backup-${profile}.timer" &>/dev/null; then
            timer_status="${GREEN}active${NC}"
        elif systemctl is-enabled "pbs-backup-${profile}.timer" &>/dev/null; then
            timer_status="${YELLOW}enabled (not running)${NC}"
        fi

        printf "  ${CYAN}%d)${NC} ${BOLD}%-20s${NC} → %s:%s/%s  [%b]\n" \
            "$count" "$profile" "$PBS_SERVER" "$PBS_PORT" "$PBS_DATASTORE" "$timer_status"
        printf "     Paths: %s\n" "${BACKUP_PATHS:-<not set>}"
        printf "     Schedule: %s | Retention: last=%s daily=%s weekly=%s monthly=%s\n" \
            "${BACKUP_SCHEDULE}" "${KEEP_LAST}" "${KEEP_DAILY}" "${KEEP_WEEKLY}" "${KEEP_MONTHLY}"
        echo
    done

    info "Total profiles: $count"
}

# cmd_install - Install a new backup profile.
# Arguments: $1 - profile name
cmd_install() {
    local profile="$1"
    validate_profile_name "$profile" || exit 1

    echo
    printf "${BOLD}═══════════════════════════════════════════${NC}\n"
    printf "${BOLD}  Installing Profile: %s${NC}\n" "$profile"
    printf "${BOLD}═══════════════════════════════════════════${NC}\n"
    echo

    local config_file="${CONFIG_DIR}/${profile}.conf"
    local cred_file="${CONFIG_DIR}/${profile}.credentials"
    local example_conf="${SCRIPT_DIR}/pbs-backup.conf.example"
    local example_cred="${SCRIPT_DIR}/credentials.example"

    # Create config directory
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    # Check if profile already exists
    if profile_exists "$profile"; then
        warn "Profile '$profile' already exists"
        printf "  Config:       %s\n" "$config_file"
        printf "  Credentials:  %s\n" "$cred_file"
        echo
        read -rp "$(printf "${YELLOW}Overwrite? (yes/no)${NC} [no]: ")" confirm
        if [[ "${confirm:-no}" != "yes" ]]; then
            info "Cancelled"
            return 0
        fi
    fi

    # Copy config template if user doesn't have one yet
    if [[ ! -f "$config_file" ]]; then
        if [[ -f "$example_conf" ]]; then
            cp "$example_conf" "$config_file"
            info "Config template copied to: $config_file"
        else
            error "Config template not found: $example_conf"
            error "Create $config_file manually from the example"
            exit 1
        fi
    fi

    if [[ ! -f "$cred_file" ]]; then
        if [[ -f "$example_cred" ]]; then
            cp "$example_cred" "$cred_file"
            info "Credentials template copied to: $cred_file"
        else
            error "Credentials template not found: $example_cred"
            exit 1
        fi
    fi

    # Set restrictive permissions
    chown root:root "$config_file" "$cred_file"
    chmod 600 "$config_file" "$cred_file"

    # Generate encryption key if user wants it
    echo
    printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${YELLOW}SECURITY RECOMMENDATION: Enable Client-Side Encryption${NC}\n"
    printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo
    echo "Backups sent to PBS are NOT encrypted by default."
    echo "Enable encryption to protect your data if PBS is compromised or backups are leaked."
    echo
    warn "WARNING: Without the encryption key, backup restoration is IMPOSSIBLE!"
    echo "         You MUST store a backup copy of the key in a secure location."
    echo
    read -p "Generate encryption key now? (yes/no) [yes]: " gen_key
    gen_key="${gen_key:-yes}"

    if [[ "$gen_key" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        local temp_keyfile="/tmp/pbs-backup-install-$$.key"
        # Ensure temp keyfile is removed even if interrupted
        trap "rm -f '$temp_keyfile'" EXIT
        
        if proxmox-backup-client key create "$temp_keyfile" --kdf none 2>/dev/null; then
            local encryption_key
            encryption_key=$(cat "$temp_keyfile")
            rm -f "$temp_keyfile"
            trap - EXIT  # Remove trap after successful cleanup

            # Append encryption key to credentials file
            if grep -q "^ENCRYPTION_KEY=" "$cred_file"; then
                sed -i "s|^ENCRYPTION_KEY=.*|ENCRYPTION_KEY=\"$encryption_key\"|" "$cred_file"
            else
                echo "" >> "$cred_file"
                echo "ENCRYPTION_KEY=\"$encryption_key\"" >> "$cred_file"
            fi

            ok "Encryption key generated and saved to: $cred_file"
            echo
            warn "BACKUP THIS KEY NOW! Store it in a password manager or secure vault."
            echo "Key preview: ${encryption_key:0:40}..."
            echo
            read -p "Press Enter after you've backed up the key..."
        else
            rm -f "$temp_keyfile"
            trap - EXIT
            error "Failed to generate encryption key. You can add it manually later."
        fi
    else
        warn "Skipping encryption key generation. Backups will NOT be encrypted."
        echo "You can generate and add a key later by editing: $cred_file"
    fi

    echo
    warn "IMPORTANT: Edit these files before enabling the timer:"
    printf "  ${CYAN}1.${NC} Config:      %s\n" "$config_file"
    printf "  ${CYAN}2.${NC} Credentials: %s\n" "$cred_file"
    echo

    # Install the backup runner script to a system path
    if [[ ! -f "$SCRIPT_INSTALL_PATH" ]] || \
        ! cmp -s "$BACKUP_SCRIPT" "$SCRIPT_INSTALL_PATH"; then
        cp "$BACKUP_SCRIPT" "$SCRIPT_INSTALL_PATH"
        chmod 700 "$SCRIPT_INSTALL_PATH"
        chown root:root "$SCRIPT_INSTALL_PATH"
        ok "Backup script installed to $SCRIPT_INSTALL_PATH"
    fi

    # Create log directory
    mkdir -p "$LOG_DIR"

    # Create systemd service
    cat > "${SYSTEMD_DIR}/pbs-backup-${profile}.service" <<EOF
[Unit]
Description=PBS Backup — Profile: ${profile}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_INSTALL_PATH} ${profile}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pbs-backup-${profile}

# Security hardening
ProtectSystem=strict
ReadWritePaths=${LOG_DIR} /run/lock/pbs-backup
PrivateTmp=true
NoNewPrivileges=false
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

    # Parse config to get schedule
    parse_config_file "$config_file"

    # Create systemd timer
    cat > "${SYSTEMD_DIR}/pbs-backup-${profile}.timer" <<EOF
[Unit]
Description=PBS Backup Timer — Profile: ${profile}
Requires=pbs-backup-${profile}.service

[Timer]
OnCalendar=${BACKUP_SCHEDULE}
Persistent=true
RandomizedDelaySec=60

[Install]
WantedBy=timers.target
EOF

    # Reload systemd
    systemctl daemon-reload

    ok "Systemd units created:"
    printf "  Service: ${SYSTEMD_DIR}/pbs-backup-${profile}.service\n"
    printf "  Timer:   ${SYSTEMD_DIR}/pbs-backup-${profile}.timer\n"
    echo

    # Ask whether to enable now
    read -rp "$(printf "${BLUE}Enable and start the timer now? (yes/no)${NC} [no]: ")" enable_now
    if [[ "${enable_now:-no}" == "yes" ]]; then
        systemctl enable "pbs-backup-${profile}.timer"
        systemctl start "pbs-backup-${profile}.timer"
        ok "Timer enabled and started"
        echo
        info "Next scheduled backup:"
        systemctl list-timers "pbs-backup-${profile}.timer" --no-pager 2>/dev/null || true
    else
        info "Timer created but not enabled. Enable later with:"
        printf "  systemctl enable --now pbs-backup-${profile}.timer\n"
    fi

    echo
    ok "Profile '$profile' installed successfully"
}

# cmd_remove - Remove a backup profile and its systemd units.
# Arguments: $1 - profile name
cmd_remove() {
    local profile="$1"
    validate_profile_name "$profile" || exit 1

    if ! profile_exists "$profile"; then
        error "Profile '$profile' does not exist"
        exit 1
    fi

    echo
    warn "This will STOP and REMOVE the backup profile '$profile'"
    warn "Config files will NOT be deleted (manual cleanup required)"
    echo
    read -rp "$(printf "${YELLOW}Type 'yes' to confirm: ${NC}")" confirm
    if [[ "${confirm}" != "yes" ]]; then
        info "Cancelled"
        return 0
    fi

    # Stop and disable systemd units
    systemctl stop "pbs-backup-${profile}.timer" 2>/dev/null || true
    systemctl stop "pbs-backup-${profile}.service" 2>/dev/null || true
    systemctl disable "pbs-backup-${profile}.timer" 2>/dev/null || true
    systemctl disable "pbs-backup-${profile}.service" 2>/dev/null || true

    # Remove systemd unit files
    rm -f "${SYSTEMD_DIR}/pbs-backup-${profile}.service"
    rm -f "${SYSTEMD_DIR}/pbs-backup-${profile}.timer"
    systemctl daemon-reload

    ok "Systemd units removed for profile '$profile'"
    echo
    info "Config files preserved at:"
    printf "  %s\n" "${CONFIG_DIR}/${profile}.conf"
    printf "  %s\n" "${CONFIG_DIR}/${profile}.credentials"
    info "Delete them manually if no longer needed:"
    printf "  rm -f ${CONFIG_DIR}/${profile}.conf ${CONFIG_DIR}/${profile}.credentials\n"
}

# cmd_status - Show status of one or all backup profiles.
# Arguments: $1 - profile name (optional; all profiles if omitted)
cmd_status() {
    local profile="${1:-}"

    echo
    printf "${BOLD}═══════════════════════════════════════════${NC}\n"
    printf "${BOLD}  PBS Backup Status${NC}\n"
    printf "${BOLD}═══════════════════════════════════════════${NC}\n"
    echo

    if [[ -n "$profile" ]]; then
        # Single profile status
        validate_profile_name "$profile" || exit 1
        if ! profile_exists "$profile"; then
            error "Profile '$profile' does not exist"
            exit 1
        fi
        _show_profile_status "$profile"
    else
        # All profiles
        if [[ ! -d "$CONFIG_DIR" ]] || ! ls "${CONFIG_DIR}"/*.conf &>/dev/null; then
            warn "No backup profiles configured"
            return 0
        fi

        for conf in "${CONFIG_DIR}"/*.conf; do
            [[ ! -f "$conf" ]] && continue
            local p
            p="$(basename "$conf" .conf)"
            _show_profile_status "$p"
            echo "───────────────────────────────────────────"
        done
    fi
}

# _show_profile_status - Display detailed status for a single profile.
# Arguments: $1 - profile name
_show_profile_status() {
    local profile="$1"
    local config_file="${CONFIG_DIR}/${profile}.conf"
    local cred_file="${CONFIG_DIR}/${profile}.credentials"

    parse_config_file "$config_file"

    printf "  ${BOLD}Profile:${NC}     %s\n" "$profile"
    printf "  ${BOLD}Server:${NC}      %s:%s\n" "${PBS_SERVER:-<not set>}" "${PBS_PORT}"
    printf "  ${BOLD}Datastore:${NC}   %s\n" "${PBS_DATASTORE:-<not set>}"
    printf "  ${BOLD}Auth:${NC}        %s\n" "${PBS_AUTH_ID:-<not set>}"
    printf "  ${BOLD}Paths:${NC}       %s\n" "${BACKUP_PATHS:-<not set>}"
    printf "  ${BOLD}Exclusions:${NC}  %s\n" "${EXCLUDE_PATTERNS:-<none>}"
    printf "  ${BOLD}Schedule:${NC}    %s\n" "${BACKUP_SCHEDULE}"
    printf "  ${BOLD}Retention:${NC}   last=%s daily=%s weekly=%s monthly=%s\n" \
        "${KEEP_LAST}" "${KEEP_DAILY}" "${KEEP_WEEKLY}" "${KEEP_MONTHLY}"

    # Credentials file check
    if [[ -f "$cred_file" ]]; then
        local cred_perms
        cred_perms="$(stat -c '%a' "$cred_file")"
        if [[ "$cred_perms" == "600" ]]; then
            printf "  ${BOLD}Credentials:${NC} %s ${GREEN}(perms OK)${NC}\n" "$cred_file"
        else
            printf "  ${BOLD}Credentials:${NC} %s ${RED}(unsafe perms: %s)${NC}\n" "$cred_file" "$cred_perms"
        fi
    else
        printf "  ${BOLD}Credentials:${NC} ${RED}MISSING${NC} — expected at %s\n" "$cred_file"
    fi

    # Timer status
    echo
    local timer_unit="pbs-backup-${profile}.timer"
    if systemctl is-active "$timer_unit" &>/dev/null; then
        printf "  ${BOLD}Timer:${NC}       ${GREEN}active${NC}\n"
        printf "  ${BOLD}Next run:${NC}    "
        systemctl list-timers "$timer_unit" --no-pager 2>/dev/null | \
            grep "$timer_unit" | awk '{print $1, $2, $3}' || echo "unknown"
    elif systemctl is-enabled "$timer_unit" &>/dev/null; then
        printf "  ${BOLD}Timer:${NC}       ${YELLOW}enabled (not running)${NC}\n"
    else
        printf "  ${BOLD}Timer:${NC}       ${RED}disabled${NC}\n"
    fi

    # Last backup result
    local service_unit="pbs-backup-${profile}.service"
    if systemctl show "$service_unit" &>/dev/null; then
        local last_result
        last_result="$(systemctl show "$service_unit" -p Result --value 2>/dev/null || echo "unknown")"
        local last_run
        last_run="$(systemctl show "$service_unit" -p ExecMainStartTimestamp --value 2>/dev/null || echo "n/a")"

        if [[ "$last_result" == "success" ]]; then
            printf "  ${BOLD}Last run:${NC}    ${GREEN}%s${NC} (%s)\n" "$last_result" "$last_run"
        elif [[ "$last_result" == "unknown" ]] || [[ -z "$last_run" ]] || [[ "$last_run" == "n/a" ]]; then
            printf "  ${BOLD}Last run:${NC}    ${YELLOW}never${NC}\n"
        else
            printf "  ${BOLD}Last run:${NC}    ${RED}%s${NC} (%s)\n" "$last_result" "$last_run"
        fi
    fi
    echo
}

# cmd_test - Test connectivity to the PBS server.
# Arguments: $1 - profile name
cmd_test() {
    local profile="$1"
    validate_profile_name "$profile" || exit 1

    if ! profile_exists "$profile"; then
        error "Profile '$profile' does not exist"
        exit 1
    fi

    local config_file="${CONFIG_DIR}/${profile}.conf"
    local cred_file="${CONFIG_DIR}/${profile}.credentials"

    echo
    printf "${BOLD}Testing connection for profile: %s${NC}\n\n" "$profile"

    # Parse config
    parse_config_file "$config_file"
    
    # Read PBS_PASSWORD from credentials file (don't use parse_config_file — it resets variables!)
    if [[ -f "$cred_file" ]]; then
        PBS_PASSWORD=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            if [[ "$line" =~ ^[[:space:]]*PBS_PASSWORD[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
                PBS_PASSWORD="${BASH_REMATCH[1]}"
                break
            elif [[ "$line" =~ ^[[:space:]]*PBS_PASSWORD[[:space:]]*=[[:space:]]*([^[:space:]#]*) ]]; then
                PBS_PASSWORD="${BASH_REMATCH[1]}"
                break
            fi
        done < "$cred_file"
        
        if [[ -z "$PBS_PASSWORD" ]]; then
            error "PBS_PASSWORD not found in credentials file"
            exit 1
        fi
    else
        error "Credentials file not found: $cred_file"
        exit 1
    fi

    # Build repository string
    export PBS_REPOSITORY="${PBS_AUTH_ID}@${PBS_SERVER}:${PBS_PORT}:${PBS_DATASTORE}"
    export PBS_PASSWORD
    [[ -n "$PBS_FINGERPRINT" ]] && export PBS_FINGERPRINT

    # Step 1: Network reachability
    info "Step 1/3: Checking network reachability..."
    if timeout 5 bash -c "echo >/dev/tcp/${PBS_SERVER}/${PBS_PORT}" 2>/dev/null; then
        ok "Server ${PBS_SERVER}:${PBS_PORT} is reachable"
    else
        error "Cannot reach ${PBS_SERVER}:${PBS_PORT}"
        error "Check: firewall, DNS, network connectivity"
        exit 1
    fi

    # Step 2: Authentication
    info "Step 2/3: Testing authentication..."
    local login_output
    if login_output=$(proxmox-backup-client login 2>&1); then
        ok "Authentication successful"
    else
        error "Authentication failed"
        echo "$login_output" | head -5 >&2
        exit 1
    fi

    # Step 3: Datastore access
    info "Step 3/3: Verifying datastore access..."
    if proxmox-backup-client list 2>/dev/null; then
        ok "Datastore '${PBS_DATASTORE}' is accessible"
    else
        warn "Could not list backups (may be empty — this is normal for first run)"
    fi

    echo
    ok "All connection tests passed for profile '$profile'"
}

# cmd_run - Execute an immediate backup for a profile.
# Arguments: $1 - profile name
cmd_run() {
    local profile="$1"
    validate_profile_name "$profile" || exit 1

    if ! profile_exists "$profile"; then
        error "Profile '$profile' does not exist"
        exit 1
    fi

    echo
    printf "${BOLD}Running manual backup for profile: %s${NC}\n\n" "$profile"
    warn "This will run the backup synchronously in the foreground."
    echo

    read -rp "$(printf "${BLUE}Proceed? (yes/no)${NC} [no]: ")" confirm
    if [[ "${confirm:-no}" != "yes" ]]; then
        info "Cancelled"
        return 0
    fi

    echo
    # Execute the backup script directly (not via systemd, for real-time output)
    local rc=0
    "$SCRIPT_INSTALL_PATH" "$profile" || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo
        ok "Manual backup completed successfully"
    else
        echo
        error "Manual backup failed (exit code: $rc)"
        info "Check logs: ${LOG_DIR}/${profile}.log"
        exit 1
    fi
}

# cmd_validate - Validate a profile's configuration without running a backup.
# Arguments: $1 - profile name
cmd_validate() {
    local profile="$1"
    validate_profile_name "$profile" || exit 1

    echo
    printf "${BOLD}Validating profile: %s${NC}\n\n" "$profile"

    local config_file="${CONFIG_DIR}/${profile}.conf"
    local cred_file="${CONFIG_DIR}/${profile}.credentials"
    local errors=0

    # Check config file
    if [[ -f "$config_file" ]]; then
        ok "Config file exists: $config_file"

        # Check permissions
        local perms owner group
        perms="$(stat -c '%a' "$config_file")"
        owner="$(stat -c '%u' "$config_file")"
        group="$(stat -c '%g' "$config_file")"

        if [[ "$owner" -eq 0 ]] && [[ "$group" -eq 0 ]]; then
            ok "Config ownership: root:root"
        else
            error "Config ownership must be root:root (currently $(stat -c '%U:%G' "$config_file"))"
            errors=$((errors + 1))
        fi

        if [[ "$perms" == "600" ]]; then
            ok "Config permissions: 600"
        else
            error "Config permissions must be 600 (currently $perms)"
            errors=$((errors + 1))
        fi

        # Parse and validate content
        parse_config_file "$config_file"

        [[ -n "$PBS_SERVER" ]]    && ok "PBS_SERVER: $PBS_SERVER"    || { error "PBS_SERVER is empty"; errors=$((errors + 1)); }
        [[ -n "$PBS_DATASTORE" ]] && ok "PBS_DATASTORE: $PBS_DATASTORE" || { error "PBS_DATASTORE is empty"; errors=$((errors + 1)); }
        [[ -n "$PBS_AUTH_ID" ]]   && ok "PBS_AUTH_ID: $PBS_AUTH_ID"  || { error "PBS_AUTH_ID is empty"; errors=$((errors + 1)); }
        [[ -n "$BACKUP_PATHS" ]]  && ok "BACKUP_PATHS: $BACKUP_PATHS" || { error "BACKUP_PATHS is empty"; errors=$((errors + 1)); }

        # Validate backup paths exist
        for path in $BACKUP_PATHS; do
            if [[ -d "$path" ]]; then
                ok "Path exists: $path"
            else
                error "Path does not exist: $path"
                errors=$((errors + 1))
            fi
        done

        # Validate schedule
        if [[ -n "$BACKUP_SCHEDULE" ]]; then
            if systemd-analyze calendar "$BACKUP_SCHEDULE" &>/dev/null; then
                ok "Schedule is valid: $BACKUP_SCHEDULE"
                local next
                next="$(systemd-analyze calendar "$BACKUP_SCHEDULE" 2>/dev/null | grep 'Next elapse' | sed 's/.*: //')"
                [[ -n "$next" ]] && info "  Next trigger: $next"
            else
                error "Invalid schedule format: $BACKUP_SCHEDULE"
                errors=$((errors + 1))
            fi
        fi

        # Validate retention values are numeric
        for var_name in KEEP_LAST KEEP_DAILY KEEP_WEEKLY KEEP_MONTHLY; do
            local val="${!var_name}"
            if [[ "$val" =~ ^[0-9]+$ ]]; then
                ok "$var_name: $val"
            else
                error "$var_name must be a number (got: '$val')"
                errors=$((errors + 1))
            fi
        done
    else
        error "Config file not found: $config_file"
        errors=$((errors + 1))
    fi

    echo

    # Check credentials file
    if [[ -f "$cred_file" ]]; then
        ok "Credentials file exists: $cred_file"

        local cred_perms cred_owner cred_group
        cred_perms="$(stat -c '%a' "$cred_file")"
        cred_owner="$(stat -c '%u' "$cred_file")"
        cred_group="$(stat -c '%g' "$cred_file")"

        if [[ "$cred_owner" -eq 0 ]] && [[ "$cred_group" -eq 0 ]]; then
            ok "Credentials ownership: root:root"
        else
            error "Credentials ownership must be root:root"
            errors=$((errors + 1))
        fi

        if [[ "$cred_perms" == "600" ]]; then
            ok "Credentials permissions: 600"
        else
            error "Credentials permissions must be 600 (currently $cred_perms)"
            errors=$((errors + 1))
        fi

        # Check for encryption key
        if grep -q "^ENCRYPTION_KEY=\".\+\"" "$cred_file" 2>/dev/null; then
            ok "Encryption: ENABLED (client-side encryption configured)"
        else
            warn "Encryption: DISABLED - Backups will NOT be encrypted!"
            warn "  Add ENCRYPTION_KEY to $cred_file to enable encryption"
            warn "  Generate key with: proxmox-backup-client key create /tmp/backup.key --kdf none"
        fi
    else
        error "Credentials file not found: $cred_file"
        errors=$((errors + 1))
    fi

    echo

    # Check systemd units
    if [[ -f "${SYSTEMD_DIR}/pbs-backup-${profile}.service" ]]; then
        ok "Systemd service unit exists"
    else
        warn "Systemd service unit not found (run 'install' to create)"
    fi

    if [[ -f "${SYSTEMD_DIR}/pbs-backup-${profile}.timer" ]]; then
        ok "Systemd timer unit exists"
    else
        warn "Systemd timer unit not found (run 'install' to create)"
    fi

    # Check backup script
    if [[ -f "$SCRIPT_INSTALL_PATH" ]]; then
        ok "Backup script installed: $SCRIPT_INSTALL_PATH"
    else
        warn "Backup script not installed at $SCRIPT_INSTALL_PATH (run 'install' to deploy)"
    fi

    echo
    if [[ $errors -eq 0 ]]; then
        ok "Validation passed — profile '$profile' is ready"
    else
        error "Validation found $errors error(s) — fix them before running backups"
        exit 1
    fi
}

# cmd_logs - Show recent backup logs for a profile.
# Arguments: $1 - profile name
cmd_logs() {
    local profile="$1"
    validate_profile_name "$profile" || exit 1

    local log_file="${LOG_DIR}/${profile}.log"

    echo
    printf "${BOLD}Logs for profile: %s${NC}\n\n" "$profile"

    # Show systemd journal entries
    info "=== Systemd Journal (last 50 entries) ==="
    journalctl -u "pbs-backup-${profile}.service" -n 50 --no-pager 2>/dev/null || \
        warn "No journal entries found"

    echo

    # Show log file if it exists
    if [[ -f "$log_file" ]]; then
        info "=== Log File: $log_file (last 50 lines) ==="
        tail -n 50 "$log_file"
    else
        info "No log file found at $log_file"
    fi
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

cmd_help() {
    cat <<EOF

${BOLD}PBS Backup Manager v${SCRIPT_VERSION}${NC}

Manage Proxmox Backup Server client backup profiles with systemd timers.

${BOLD}USAGE:${NC}
    $(basename "$0") <command> [profile-name]

${BOLD}COMMANDS:${NC}
    install  <profile>  Install a new backup profile (creates config + systemd units)
    remove   <profile>  Remove a profile's systemd units
    status   [profile]  Show status of one or all profiles
    test     <profile>  Test PBS server connectivity for a profile
    run      <profile>  Execute an immediate manual backup
    validate <profile>  Validate configuration files without running
    list                List all configured profiles
    logs     <profile>  Show recent backup logs
    help                Show this help message

${BOLD}EXAMPLES:${NC}
    # Install a new profile named "rpool"
    sudo $(basename "$0") install rpool

    # Edit the config, then validate
    sudo nano /etc/pbs-backup/rpool.conf
    sudo nano /etc/pbs-backup/rpool.credentials
    sudo $(basename "$0") validate rpool

    # Test connection and run first backup
    sudo $(basename "$0") test rpool
    sudo $(basename "$0") run rpool

    # Check all profiles' status
    sudo $(basename "$0") status

${BOLD}FILES:${NC}
    ${CONFIG_DIR}/<profile>.conf          Configuration (server, paths, schedule)
    ${CONFIG_DIR}/<profile>.credentials   Credentials (password/token, mode 0600)
    ${LOG_DIR}/<profile>.log              Backup execution logs
    ${SYSTEMD_DIR}/pbs-backup-<profile>.service   Systemd service unit
    ${SYSTEMD_DIR}/pbs-backup-<profile>.timer     Systemd timer unit

EOF
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------

main() {
    check_root
    check_pbs_client

    local command="${1:-help}"
    local profile="${2:-}"

    case "$command" in
        install)
            [[ -z "$profile" ]] && { error "Usage: $0 install <profile>"; exit 1; }
            cmd_install "$profile"
            ;;
        remove|delete)
            [[ -z "$profile" ]] && { error "Usage: $0 remove <profile>"; exit 1; }
            cmd_remove "$profile"
            ;;
        status)
            cmd_status "$profile"
            ;;
        test)
            [[ -z "$profile" ]] && { error "Usage: $0 test <profile>"; exit 1; }
            cmd_test "$profile"
            ;;
        run|backup)
            [[ -z "$profile" ]] && { error "Usage: $0 run <profile>"; exit 1; }
            cmd_run "$profile"
            ;;
        validate|check)
            [[ -z "$profile" ]] && { error "Usage: $0 validate <profile>"; exit 1; }
            cmd_validate "$profile"
            ;;
        list|ls)
            cmd_list
            ;;
        logs|log)
            [[ -z "$profile" ]] && { error "Usage: $0 logs <profile>"; exit 1; }
            cmd_logs "$profile"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
