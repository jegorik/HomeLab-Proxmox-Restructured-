#!/usr/bin/env bash
# =============================================================================
# pbs-backup.sh — Proxmox Backup Server Client Backup Runner
# =============================================================================
#
# Executes a file-level backup to a Proxmox Backup Server using
# proxmox-backup-client. Designed to be invoked by a systemd timer
# or manually via the management script.
#
# Usage:
#   pbs-backup.sh <profile-name>
#
# Arguments:
#   profile-name  Name of the backup profile (matches /etc/pbs-backup/<name>.conf)
#
# Exit Codes:
#   0  - Backup and prune completed successfully
#   1  - General error (config, permissions, validation)
#   2  - Lock acquisition failed (another backup is running)
#   3  - Backup execution failed
#   4  - Prune execution failed
#
# Security:
#   - No use of eval; commands built with bash arrays
#   - Credentials loaded from a separate file with strict permission checks
#   - Lock file prevents concurrent execution
#   - All user-supplied paths are validated before use
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly SCRIPT_NAME="pbs-backup"
readonly SCRIPT_VERSION="1.0.0"
readonly CONFIG_DIR="/etc/pbs-backup"
readonly LOG_DIR="/var/log/pbs-backup"
readonly LOCK_DIR="/run/lock/pbs-backup"

# Global variable for temporary encryption keyfile (cleaned up by trap)
ENCRYPTION_KEYFILE=""

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

# log_info - Log an informational message to stdout and log file.
# Arguments: $1 - message text
log_info() {
    local ts
    ts="$(date +'%Y-%m-%d %H:%M:%S')"
    printf '[%s] [INFO]  %s\n' "$ts" "$1"
    printf '[%s] [INFO]  %s\n' "$ts" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

# log_warn - Log a warning message to stdout and log file.
# Arguments: $1 - message text
log_warn() {
    local ts
    ts="$(date +'%Y-%m-%d %H:%M:%S')"
    printf '[%s] [WARN]  %s\n' "$ts" "$1" >&2
    printf '[%s] [WARN]  %s\n' "$ts" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

# log_error - Log an error message to stderr and log file.
# Arguments: $1 - message text
log_error() {
    local ts
    ts="$(date +'%Y-%m-%d %H:%M:%S')"
    printf '[%s] [ERROR] %s\n' "$ts" "$1" >&2
    printf '[%s] [ERROR] %s\n' "$ts" "$1" >> "$LOG_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

# validate_profile_name - Ensure profile name contains only safe characters.
# Arguments: $1 - profile name
# Returns:   0 if valid, 1 if invalid
validate_profile_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        log_error "Profile name cannot be empty"
        return 1
    fi
    if ! [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]]; then
        log_error "Profile name contains invalid characters: '$name' (allowed: alphanumeric, dash, underscore, dot)"
        return 1
    fi
    return 0
}

# validate_file_permissions - Check that a file has the expected restrictive permissions.
# Arguments: $1 - file path, $2 - human-readable label
# Returns:   0 if permissions are safe, 1 otherwise
validate_file_permissions() {
    local file_path="$1"
    local label="${2:-file}"

    if [[ ! -f "$file_path" ]]; then
        log_error "$label not found: $file_path"
        return 1
    fi

    # Check ownership is root:root
    local file_owner file_group
    file_owner="$(stat -c '%u' "$file_path")"
    file_group="$(stat -c '%g' "$file_path")"
    if [[ "$file_owner" -ne 0 ]] || [[ "$file_group" -ne 0 ]]; then
        log_error "$label must be owned by root:root (currently $(stat -c '%U:%G' "$file_path")): $file_path"
        return 1
    fi

    # Check permissions are not group/world readable
    local file_perms
    file_perms="$(stat -c '%a' "$file_path")"
    if [[ "${file_perms:1:1}" != "0" ]] || [[ "${file_perms:2:1}" != "0" ]]; then
        log_error "$label has unsafe permissions ($file_perms). Must be 600 or stricter: $file_path"
        return 1
    fi

    return 0
}

# validate_path_exists - Ensure a path exists and is a directory.
# Arguments: $1 - directory path
# Returns:   0 if exists, 1 otherwise
validate_path_exists() {
    local dir_path="$1"
    if [[ ! -d "$dir_path" ]]; then
        log_error "Backup path does not exist or is not a directory: $dir_path"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Config parser (secure — no 'source', key=value parsing only)
# ---------------------------------------------------------------------------

# parse_config - Safely parse a key=value config file without sourcing it.
# Only allows predefined keys to prevent code injection.
# Arguments: $1 - config file path
# Globals:   Sets PBS_SERVER, PBS_PORT, PBS_DATASTORE, PBS_AUTH_ID, etc.
parse_config() {
    local config_file="$1"
    local line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Extract key and value (strip surrounding quotes)
        if [[ "$line" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*([^[:space:]#]*) ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        # Whitelist of allowed config keys
        case "$key" in
            PBS_SERVER)              PBS_SERVER="$value" ;;
            PBS_PORT)                PBS_PORT="$value" ;;
            PBS_DATASTORE)           PBS_DATASTORE="$value" ;;
            PBS_AUTH_ID)             PBS_AUTH_ID="$value" ;;
            PBS_FINGERPRINT)         PBS_FINGERPRINT="$value" ;;
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
            *)
                log_warn "Unknown config key ignored: $key"
                ;;
        esac
    done < "$config_file"
}

# parse_credentials - Safely parse the credentials file.
# Arguments: $1 - credentials file path
# Globals:   Sets PBS_PASSWORD
parse_credentials() {
    local cred_file="$1"
    local line key value

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
            PBS_PASSWORD) PBS_PASSWORD="$value" ;;
            ENCRYPTION_KEY) ENCRYPTION_KEY="$value" ;;
            *)  log_warn "Unknown credentials key ignored: $key" ;;
        esac
    done < "$cred_file"
}

# ---------------------------------------------------------------------------
# Lock management
# ---------------------------------------------------------------------------

# acquire_lock - Create a lock file to prevent concurrent backups.
# Arguments: $1 - profile name
# Returns:   0 on success, 2 if lock already held
acquire_lock() {
    local profile="$1"
    local lock_file="${LOCK_DIR}/${profile}.lock"
    local timeout="${LOCK_TIMEOUT:-300}"

    mkdir -p "$LOCK_DIR"

    # Try to acquire lock with timeout
    local waited=0
    while [[ -f "$lock_file" ]]; do
        local lock_pid
        lock_pid="$(cat "$lock_file" 2>/dev/null || echo "")"

        # Check if the process holding the lock is still alive
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            if [[ "$waited" -ge "$timeout" ]]; then
                log_error "Lock timeout after ${timeout}s. Another backup (PID $lock_pid) is running for profile '$profile'"
                return 2
            fi
            log_warn "Waiting for lock (PID $lock_pid)... ${waited}/${timeout}s"
            sleep 5
            waited=$((waited + 5))
        else
            # Stale lock — previous process died
            log_warn "Removing stale lock file (PID $lock_pid no longer running)"
            rm -f "$lock_file"
            break
        fi
    done

    # Write our PID to lock file
    echo $$ > "$lock_file"
    return 0
}

# release_lock - Remove the lock file.
# Arguments: $1 - profile name
release_lock() {
    local profile="$1"
    local lock_file="${LOCK_DIR}/${profile}.lock"
    rm -f "$lock_file"
}

# ---------------------------------------------------------------------------
# Backup execution
# ---------------------------------------------------------------------------

# build_backup_command - Construct the proxmox-backup-client backup command
# as a bash array (safe, no eval).
# Arguments: none (uses global config variables)
# Output:    Prints the command array elements, one per line
build_backup_command() {
    local -a cmd=("proxmox-backup-client" "backup")

    # Add each backup path as a separate .pxar archive
    local path archive_name
    for path in $BACKUP_PATHS; do
        # Validate the path exists
        if ! validate_path_exists "$path"; then
            log_error "Skipping invalid path: $path"
            continue
        fi

        # Generate archive name from path (/ → root, /rpool/data → rpool-data)
        archive_name="$(echo "$path" | sed 's|^/||; s|/|-|g')"
        [[ -z "$archive_name" ]] && archive_name="root"

        cmd+=("${archive_name}.pxar:${path}")
        
        # Traverse mount points (bind mounts) - add --include-dev for the path itself
        # and all nested mount points within it
        if mountpoint -q "$path" 2>/dev/null; then
            cmd+=("--include-dev" "$path")
            
            # Find all nested mount points within this path
            local nested_mp
            while IFS= read -r nested_mp; do
                cmd+=("--include-dev" "$nested_mp")
            done < <(findmnt -rno TARGET -R "$path" 2>/dev/null | grep -v "^${path}$")
        fi
    done

    # Add exclusion patterns
    local pattern
    for pattern in $EXCLUDE_PATTERNS; do
        cmd+=("--exclude" "$pattern")
    done

    # Skip lost+found directories
    if [[ "${SKIP_LOST_AND_FOUND:-true}" == "true" ]]; then
        cmd+=("--skip-lost-and-found")
    fi

    # Change detection mode
    if [[ -n "${CHANGE_DETECTION_MODE:-}" ]]; then
        cmd+=("--change-detection-mode" "$CHANGE_DETECTION_MODE")
    fi

    # Client-side encryption (HIGHLY RECOMMENDED)
    if [[ -n "${ENCRYPTION_KEY:-}" ]]; then
        # Write encryption key to temporary keyfile (removed by trap on exit)
        ENCRYPTION_KEYFILE="/tmp/pbs-backup-${PROFILE}-$$.key"
        echo "$ENCRYPTION_KEY" > "$ENCRYPTION_KEYFILE"
        chmod 600 "$ENCRYPTION_KEYFILE"
        cmd+=("--keyfile" "$ENCRYPTION_KEYFILE" "--crypt-mode" "encrypt")
    fi

    # Print command array elements for the caller to read
    printf '%s\n' "${cmd[@]}"
}

# run_backup - Execute the backup using proxmox-backup-client.
# Returns: 0 on success, 3 on failure
run_backup() {
    local hostname
    hostname="$(hostname)"

    log_info "Starting file-level backup for host '${hostname}', profile '${PROFILE}'"
    log_info "Backup paths: ${BACKUP_PATHS}"

    # Log mount points that will be traversed
    local path nested_count
    for path in $BACKUP_PATHS; do
        if mountpoint -q "$path" 2>/dev/null; then
            nested_count=$(findmnt -rno TARGET -R "$path" 2>/dev/null | grep -v "^${path}$" | wc -l)
            if [[ $nested_count -gt 0 ]]; then
                log_info "Mount point detected: $path (with $nested_count nested mount points - will traverse with --include-dev)"
            else
                log_info "Mount point detected: $path (will traverse with --include-dev)"
            fi
        fi
    done

    # Build command as an array (secure — no eval)
    local -a backup_cmd=()
    while IFS= read -r element; do
        backup_cmd+=("$element")
    done < <(build_backup_command)

    # Validate we have at least one archive to back up
    if [[ ${#backup_cmd[@]} -lt 3 ]]; then
        log_error "No valid backup paths found. Nothing to back up."
        return 3
    fi

    # Log the command (mask sensitive data: password and encryption key)
    local log_cmd=("${backup_cmd[@]}")
    local i
    for i in "${!log_cmd[@]}"; do
        if [[ "${log_cmd[$i]}" == "--keyfile" ]] && [[ $((i+1)) -lt ${#log_cmd[@]} ]]; then
            log_cmd[$((i+1))]="***KEYFILE***"
        fi
    done
    log_info "Executing: ${log_cmd[*]}"

    # Execute backup
    local exit_code=0
    if "${backup_cmd[@]}"; then
        log_info "Backup completed successfully"
    else
        exit_code=$?
        log_error "Backup failed with exit code $exit_code"
    fi

    [[ $exit_code -eq 0 ]] && return 0 || return 3
}

# run_prune - Apply retention policy by pruning old backups.
# Returns: 0 on success, 4 on failure
run_prune() {
    local hostname
    hostname="$(hostname)"

    log_info "Applying retention policy: last=${KEEP_LAST} daily=${KEEP_DAILY} weekly=${KEEP_WEEKLY} monthly=${KEEP_MONTHLY}"

    local -a prune_cmd=(
        "proxmox-backup-client" "prune" "host/${hostname}"
    )

    # Add retention flags (only if value > 0)
    [[ "${KEEP_LAST:-0}" -gt 0 ]]    && prune_cmd+=("--keep-last" "$KEEP_LAST")
    [[ "${KEEP_DAILY:-0}" -gt 0 ]]   && prune_cmd+=("--keep-daily" "$KEEP_DAILY")
    [[ "${KEEP_WEEKLY:-0}" -gt 0 ]]  && prune_cmd+=("--keep-weekly" "$KEEP_WEEKLY")
    [[ "${KEEP_MONTHLY:-0}" -gt 0 ]] && prune_cmd+=("--keep-monthly" "$KEEP_MONTHLY")

    log_info "Executing: ${prune_cmd[*]}"

    if "${prune_cmd[@]}"; then
        log_info "Prune completed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Prune failed with exit code $exit_code"
        return 4
    fi
}

# ---------------------------------------------------------------------------
# Notification
# ---------------------------------------------------------------------------

# notify_failure - Execute the user-defined failure notification command.
# Arguments: $1 - error message
notify_failure() {
    local message="$1"

    if [[ -z "${NOTIFY_ON_FAILURE:-}" ]]; then
        return 0
    fi

    log_info "Sending failure notification..."
    # Run notification command in a subshell with timeout to prevent hangs
    if ! timeout 30 bash -c "${NOTIFY_ON_FAILURE}" -- "$message" 2>/dev/null; then
        log_warn "Failure notification command returned non-zero or timed out"
    fi
}

# ---------------------------------------------------------------------------
# Cleanup trap
# ---------------------------------------------------------------------------

# cleanup - Release lock and perform cleanup on exit.
cleanup() {
    local exit_code=$?
    
    # Remove temporary encryption keyfile (security critical)
    if [[ -n "${ENCRYPTION_KEYFILE:-}" ]] && [[ -f "$ENCRYPTION_KEYFILE" ]]; then
        rm -f "$ENCRYPTION_KEYFILE"
    fi
    
    if [[ -n "${PROFILE:-}" ]]; then
        release_lock "$PROFILE"
    fi

    if [[ $exit_code -ne 0 ]]; then
        local msg="PBS backup failed for profile '${PROFILE:-unknown}' with exit code $exit_code"
        log_error "$msg"
        notify_failure "$msg"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    # Validate arguments
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <profile-name>" >&2
        echo "Example: $0 rpool" >&2
        exit 1
    fi

    PROFILE="$1"
    validate_profile_name "$PROFILE" || exit 1

    # Check we're running as root
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "[ERROR] This script must be run as root" >&2
        exit 1
    fi

    # File paths
    local config_file="${CONFIG_DIR}/${PROFILE}.conf"
    local cred_file="${CONFIG_DIR}/${PROFILE}.credentials"

    # Set up logging
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/${PROFILE}.log"

    log_info "========================================="
    log_info "PBS Backup v${SCRIPT_VERSION} — Profile: ${PROFILE}"
    log_info "========================================="

    # Register cleanup trap
    trap cleanup EXIT

    # --- Load and validate configuration ---

    # Validate config file exists and has safe permissions
    validate_file_permissions "$config_file" "Config file" || exit 1
    validate_file_permissions "$cred_file" "Credentials file" || exit 1

    # Initialize defaults
    PBS_SERVER="" PBS_PORT="8007" PBS_DATASTORE="" PBS_AUTH_ID=""
    PBS_FINGERPRINT="" PBS_PASSWORD="" ENCRYPTION_KEY=""
    BACKUP_PATHS="" EXCLUDE_PATTERNS="" BACKUP_SCHEDULE=""
    KEEP_LAST=3 KEEP_DAILY=7 KEEP_WEEKLY=4 KEEP_MONTHLY=3
    CHANGE_DETECTION_MODE="metadata" SKIP_LOST_AND_FOUND="true"
    VERBOSE="false" LOCK_TIMEOUT=300 NOTIFY_ON_FAILURE=""

    # Parse config (safe — no source/eval)
    parse_config "$config_file"
    parse_credentials "$cred_file"

    # Validate required fields
    local missing=()
    [[ -z "$PBS_SERVER" ]]    && missing+=("PBS_SERVER")
    [[ -z "$PBS_DATASTORE" ]] && missing+=("PBS_DATASTORE")
    [[ -z "$PBS_AUTH_ID" ]]   && missing+=("PBS_AUTH_ID")
    [[ -z "$PBS_PASSWORD" ]]  && missing+=("PBS_PASSWORD")
    [[ -z "$BACKUP_PATHS" ]]  && missing+=("BACKUP_PATHS")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required config fields: ${missing[*]}"
        exit 1
    fi

    # Validate all backup paths exist
    local path
    for path in $BACKUP_PATHS; do
        validate_path_exists "$path" || exit 1
    done

    # --- Set up PBS environment ---

    # Build the PBS_REPOSITORY string
    export PBS_REPOSITORY="${PBS_AUTH_ID}@${PBS_SERVER}:${PBS_PORT}:${PBS_DATASTORE}"
    export PBS_PASSWORD

    # Set fingerprint if provided (prevents MITM)
    if [[ -n "$PBS_FINGERPRINT" ]]; then
        export PBS_FINGERPRINT
    fi

    log_info "Target: ${PBS_AUTH_ID}@${PBS_SERVER}:${PBS_PORT} → datastore '${PBS_DATASTORE}'"

    # --- Acquire lock ---
    acquire_lock "$PROFILE" || exit 2

    # --- Execute backup ---
    run_backup || exit 3

    # --- Execute prune ---
    run_prune || exit 4

    log_info "All operations completed successfully for profile '${PROFILE}'"
}

main "$@"
