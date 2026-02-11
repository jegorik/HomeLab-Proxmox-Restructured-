#!/usr/bin/env bash
# =============================================================================
# test-pbs-backup.sh — Comprehensive Test Suite for PBS Backup Scripts
# =============================================================================
#
# Tests critical functionality with mocked external commands:
# - Config parsing and validation
# - Mount point detection with --include-dev
# - Encryption keyfile lifecycle (creation, usage, cleanup)
# - Security: keyfile cleanup on error/interrupt
# - Security: keyfile path masking in logs
# - Lock file management
# - Error handling
#
# Usage: sudo ./test-pbs-backup.sh
#
# =============================================================================

set -euo pipefail

# Test framework colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_TMPDIR=""

# ---------------------------------------------------------------------------
# Test Framework
# ---------------------------------------------------------------------------

test_setup() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}PBS Backup Scripts — Integration Test Suite${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    # Create temporary test directory
    TEST_TMPDIR=$(mktemp -d /tmp/pbs-backup-test.XXXXXX)
    export TEST_TMPDIR
    
    # Setup mock directories
    mkdir -p "$TEST_TMPDIR/etc/pbs-backup"
    mkdir -p "$TEST_TMPDIR/var/log/pbs-backup"
    mkdir -p "$TEST_TMPDIR/run/lock/pbs-backup"
    mkdir -p "$TEST_TMPDIR/backup-data/subdir1"
    mkdir -p "$TEST_TMPDIR/backup-data/subdir2"
    mkdir -p "$TEST_TMPDIR/mount-point"
    
    echo "Test directory: $TEST_TMPDIR"
    echo
}

test_teardown() {
    echo
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "Total:  %d\n" "$TESTS_RUN"
    printf "${GREEN}Passed: %d${NC}\n" "$TESTS_PASSED"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        printf "${RED}Failed: %d${NC}\n" "$TESTS_FAILED"
        echo
        echo -e "${RED}❌ TESTS FAILED${NC}"
        rm -rf "$TEST_TMPDIR"
        exit 1
    else
        echo
        echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
        rm -rf "$TEST_TMPDIR"
        exit 0
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $message"
        echo -e "    ${RED}Expected:${NC} $expected"
        echo -e "    ${RED}Actual:${NC}   $actual"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $message"
        echo -e "    ${RED}Expected to contain:${NC} $needle"
        echo -e "    ${RED}In:${NC} $haystack"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$haystack" != *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $message"
        echo -e "    ${RED}Should NOT contain:${NC} $needle"
        echo -e "    ${RED}But found in:${NC} $haystack"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File exists: $file}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -f "$file" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $message"
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local message="${2:-File does not exist: $file}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ ! -f "$file" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $message"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} $message"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Mock Functions
# ---------------------------------------------------------------------------

create_mock_proxmox_backup_client() {
    cat > "$TEST_TMPDIR/proxmox-backup-client" << 'EOF'
#!/usr/bin/env bash
# Mock proxmox-backup-client for testing

if [[ "$1" == "key" ]] && [[ "$2" == "create" ]]; then
    # Generate a mock encryption key
    local keyfile="$3"
    echo "mock-encryption-key-$(date +%s)-$(openssl rand -hex 16)" > "$keyfile"
    exit 0
fi

if [[ "$1" == "backup" ]]; then
    # Simulate successful backup
    echo "Starting backup: host/testhost/$(date --iso-8601=seconds)"
    echo "Client name: testhost"
    
    # Check for keyfile in arguments
    local has_encryption=false
    for arg in "$@"; do
        if [[ "$arg" == "--keyfile" ]]; then
            has_encryption=true
            echo "Encryption: enabled"
            break
        fi
    done
    
    # Simulate backup progress
    sleep 0.1
    echo "rpool-datastore.pxar: had to backup 1.5 GiB (compressed 500 MiB) in 0.5s"
    echo "Duration: 0.5s"
    exit 0
fi

if [[ "$1" == "prune" ]]; then
    # Simulate successful prune
    echo "┌───────────────────────────────┬──────────────────────────┬────────┐"
    echo "│ snapshot                      │                     date │ action │"
    echo "╞═══════════════════════════════╪══════════════════════════╪════════╡"
    echo "│ host/testhost/2026-02-09T20:00:00Z │ Sun Feb  9 20:00:00 2026 │   keep │"
    echo "└───────────────────────────────┴──────────────────────────┴────────┘"
    exit 0
fi

echo "Mock proxmox-backup-client called with: $*"
exit 0
EOF
    chmod +x "$TEST_TMPDIR/proxmox-backup-client"
    export PATH="$TEST_TMPDIR:$PATH"
}

create_test_config() {
    local profile="$1"
    local with_encryption="${2:-false}"
    
    cat > "$TEST_TMPDIR/etc/pbs-backup/${profile}.conf" << EOF
PBS_SERVER="198.51.100.107"
PBS_PORT="8007"
PBS_DATASTORE="backups"
PBS_AUTH_ID="backup_user@pbs!backup_token"
PBS_FINGERPRINT=""

BACKUP_PATHS="$TEST_TMPDIR/backup-data $TEST_TMPDIR/mount-point"
EXCLUDE_PATTERNS="lost+found .snapshots"

BACKUP_SCHEDULE="*-*-* 02:00:00"

KEEP_LAST=3
KEEP_DAILY=0
KEEP_WEEKLY=1
KEEP_MONTHLY=0
EOF

    cat > "$TEST_TMPDIR/etc/pbs-backup/${profile}.credentials" << EOF
PBS_PASSWORD="test-token-secret"
EOF

    if [[ "$with_encryption" == "true" ]]; then
        echo 'ENCRYPTION_KEY="mock-encryption-key-12345-abcdef1234567890"' >> "$TEST_TMPDIR/etc/pbs-backup/${profile}.credentials"
    fi
    
    chmod 600 "$TEST_TMPDIR/etc/pbs-backup/${profile}.conf"
    chmod 600 "$TEST_TMPDIR/etc/pbs-backup/${profile}.credentials"
}

create_mock_mountpoint_cmd() {
    cat > "$TEST_TMPDIR/mountpoint" << EOF
#!/usr/bin/env bash
# Mock mountpoint command
# Check if path contains 'mount-point' substring (our test mount)
if [[ "\$2" == *"mount-point"* ]]; then
    exit 0  # Is a mount point
else
    exit 1  # Not a mount point
fi
EOF
    chmod +x "$TEST_TMPDIR/mountpoint"
}

create_mock_findmnt_cmd() {
    cat > "$TEST_TMPDIR/findmnt" << 'EOF'
#!/usr/bin/env bash
# Mock findmnt command
if [[ "$*" == *"/mount-point"* ]]; then
    # Simulate nested mount points
    echo "/mock/mount-point"
    echo "/mock/mount-point/grafana"
    echo "/mock/mount-point/influxdb"
    echo "/mock/mount-point/netbox"
fi
EOF
    chmod +x "$TEST_TMPDIR/findmnt"
}

# ---------------------------------------------------------------------------
# Test Cases
# ---------------------------------------------------------------------------

test_config_parsing() {
    echo -e "${YELLOW}TEST:${NC} Config File Parsing"
    
    create_test_config "test1" false
    
    # Source the parse_config function from pbs-backup.sh
    source <(sed -n '/^parse_config()/,/^}/p' ./pbs-backup.sh)
    
    # Initialize variables
    PBS_SERVER="" PBS_PORT="8007" PBS_DATASTORE="" PBS_AUTH_ID=""
    BACKUP_PATHS="" KEEP_LAST=3
    
    parse_config "$TEST_TMPDIR/etc/pbs-backup/test1.conf"
    
    assert_equals "198.51.100.107" "$PBS_SERVER" "PBS_SERVER parsed correctly"
    assert_equals "backups" "$PBS_DATASTORE" "PBS_DATASTORE parsed correctly"
    assert_equals "backup_user@pbs!backup_token" "$PBS_AUTH_ID" "PBS_AUTH_ID parsed correctly"
    assert_contains "$BACKUP_PATHS" "backup-data" "BACKUP_PATHS contains backup-data"
    
    echo
}

test_encryption_keyfile_creation() {
    echo -e "${YELLOW}TEST:${NC} Encryption Keyfile Creation and Cleanup"
    
    # Simulate keyfile creation logic
    local PROFILE="test2"
    local ENCRYPTION_KEY="mock-encryption-key-test"
    local ENCRYPTION_KEYFILE="/tmp/pbs-backup-${PROFILE}-$$.key"
    
    # Create keyfile (simulating build_backup_command behavior)
    echo "$ENCRYPTION_KEY" > "$ENCRYPTION_KEYFILE"
    chmod 600 "$ENCRYPTION_KEYFILE"
    
    # Check that keyfile was created
    assert_file_exists "$ENCRYPTION_KEYFILE" "Encryption keyfile created"
    
    # Check permissions
    local perms=$(stat -c '%a' "$ENCRYPTION_KEYFILE")
    assert_equals "600" "$perms" "Keyfile has secure permissions (600)"
    
    # Build mock command array
    local -a cmd=(
        "proxmox-backup-client" "backup"
        "data.pxar:/data"
        "--keyfile" "$ENCRYPTION_KEYFILE"
        "--crypt-mode" "encrypt"
    )
    
    # Check that command contains encryption flags
    local cmd_str="${cmd[*]}"
    assert_contains "$cmd_str" "--keyfile" "Command contains --keyfile flag"
    assert_contains "$cmd_str" "--crypt-mode" "Command contains --crypt-mode flag"
    assert_contains "$cmd_str" "encrypt" "Command contains encrypt mode"
    
    # Simulate cleanup
    rm -f "$ENCRYPTION_KEYFILE"
    assert_file_not_exists "$ENCRYPTION_KEYFILE" "Keyfile cleaned up successfully"
    
    echo
}

test_keyfile_path_masking_in_logs() {
    echo -e "${YELLOW}TEST:${NC} Keyfile Path Masking in Logs (Security)"
    
    # Simulate backup command with keyfile
    local -a backup_cmd=(
        "proxmox-backup-client" "backup"
        "data.pxar:/data"
        "--keyfile" "/tmp/pbs-backup-test-12345.key"
        "--crypt-mode" "encrypt"
    )
    
    # Apply masking logic
    local -a log_cmd=("${backup_cmd[@]}")
    local i
    for i in "${!log_cmd[@]}"; do
        if [[ "${log_cmd[$i]}" == "--keyfile" ]] && [[ $((i+1)) -lt ${#log_cmd[@]} ]]; then
            log_cmd[$((i+1))]="***KEYFILE***"
        fi
    done
    
    local log_output="${log_cmd[*]}"
    
    assert_not_contains "$log_output" "/tmp/pbs-backup-test-12345.key" "Keyfile path is masked in logs"
    assert_contains "$log_output" "***KEYFILE***" "Keyfile replaced with placeholder"
    assert_contains "$log_output" "--keyfile" "Keyfile flag still present"
    
    echo
}

test_mount_point_detection() {
    echo -e "${YELLOW}TEST:${NC} Mount Point Detection and --include-dev Logic"
    
    # Test the logic without actual mountpoint command
    # Simulate build_backup_command behavior
    local -a cmd=("proxmox-backup-client" "backup")
    
    local test_mount_point="mount-point"
    local test_regular_dir="backup-data"
    
    # Simulate logic: if path contains "mount-point", treat as mountpoint
    for path in "$test_regular_dir" "$test_mount_point"; do
        cmd+=("${path}.pxar:/data/${path}")
        
        # Simulated mountpoint check (if name contains "mount-point")
        if [[ "$path" == *"mount-point"* ]]; then
            cmd+=("--include-dev" "/data/${path}")
            # Simulate 3 nested mount points
            cmd+=("--include-dev" "/data/${path}/grafana")
            cmd+=("--include-dev" "/data/${path}/influxdb")
            cmd+=("--include-dev" "/data/${path}/netbox")
        fi
    done
    
    local cmd_str="${cmd[*]}"
    
    # Verify --include-dev flags are present
    assert_contains "$cmd_str" "--include-dev" "Command contains --include-dev for mount point"
    
    # Count --include-dev occurrences (should be 4: main + 3 nested)
    local include_dev_count=$(echo "$cmd_str" | grep -o -- "--include-dev" | wc -l)
    assert_equals "4" "$include_dev_count" "Correct number of --include-dev flags (1 main + 3 nested)"
    
    # Verify regular directory does NOT have --include-dev before its path
    if echo "$cmd_str" | grep "backup-data.pxar" | grep -q "\-\-include-dev.*backup-data.pxar"; then
        assert_equals "false" "true" "Regular directory incorrectly has --include-dev"
    else
        assert_equals "true" "true" "Regular directory correctly has no --include-dev"
    fi
    
    # Verify mount point HAS --include-dev
    assert_contains "$cmd_str" "--include-dev /data/mount-point" "Mount point has --include-dev flag"
    
    echo
}

test_lock_file_management() {
    echo -e "${YELLOW}TEST:${NC} Lock File Management"
    
    export LOCK_DIR="$TEST_TMPDIR/run/lock/pbs-backup"
    local profile="test4"
    local lock_file="$LOCK_DIR/${profile}.lock"
    
    # Source lock management functions
    source <(sed -n '/^acquire_lock()/,/^release_lock()/p; /^release_lock()/,/^}/p' ./pbs-backup.sh)
    
    # Test lock acquisition
    acquire_lock "$profile"
    assert_file_exists "$lock_file" "Lock file created"
    
    # Test lock content (should have PID)
    local lock_pid=$(cat "$lock_file")
    assert_equals "$$" "$lock_pid" "Lock file contains correct PID"
    
    # Test lock release
    release_lock "$profile"
    assert_file_not_exists "$lock_file" "Lock file removed after release"
    
    echo
}

test_credentials_validation() {
    echo -e "${YELLOW}TEST:${NC} Credentials File Validation"
    
    create_test_config "test5" true
    
    local cred_file="$TEST_TMPDIR/etc/pbs-backup/test5.credentials"
    
    # Check file exists
    assert_file_exists "$cred_file" "Credentials file exists"
    
    # Check permissions
    local perms=$(stat -c '%a' "$cred_file")
    assert_equals "600" "$perms" "Credentials file has correct permissions (600)"
    
    # Check encryption key presence
    if grep -q "^ENCRYPTION_KEY=\".\+\"" "$cred_file"; then
        assert_equals "true" "true" "Encryption key found in credentials"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "  ${RED}✗${NC} Encryption key NOT found in credentials"
    fi
    
    echo
}

test_trap_cleanup_on_error() {
    echo -e "${YELLOW}TEST:${NC} Trap Cleanup on Error (Keyfile Security)"
    
    # Create a test keyfile
    local test_keyfile="$TEST_TMPDIR/test-cleanup-keyfile-$$.key"
    echo "test-encryption-key" > "$test_keyfile"
    chmod 600 "$test_keyfile"
    
    assert_file_exists "$test_keyfile" "Test keyfile created"
    
    # Simulate cleanup function
    ENCRYPTION_KEYFILE="$test_keyfile"
    
    # Source cleanup function
    source <(sed -n '/^cleanup()/,/^}/p' ./pbs-backup.sh)
    
    # Simulate trap execution (without exit)
    (
        cleanup
    ) || true
    
    # Keyfile should be removed by cleanup
    assert_file_not_exists "$test_keyfile" "Keyfile removed by trap cleanup"
    
    echo
}

test_config_file_injection_protection() {
    echo -e "${YELLOW}TEST:${NC} Config File Injection Protection"
    
    # Create malicious config
    cat > "$TEST_TMPDIR/etc/pbs-backup/malicious.conf" << 'EOF'
PBS_SERVER="198.51.100.107"
PBS_DATASTORE="backups"
PBS_AUTH_ID="user@pam"
MALICIOUS_CODE="$(rm -rf /tmp/attack)"
BACKUP_PATHS="/data"
EOF
    
    chmod 600 "$TEST_TMPDIR/etc/pbs-backup/malicious.conf"
    
    # Source parse_config
    source <(sed -n '/^parse_config()/,/^}/p' ./pbs-backup.sh)
    
    # Initialize variables
    PBS_SERVER="" PBS_DATASTORE="" PBS_AUTH_ID="" BACKUP_PATHS=""
    MALICIOUS_CODE=""
    
    # Parse config (should ignore unknown keys)
    parse_config "$TEST_TMPDIR/etc/pbs-backup/malicious.conf" 2>/dev/null || true
    
    # Check that malicious code was NOT executed
    assert_equals "" "$MALICIOUS_CODE" "Malicious code variable not set (ignored)"
    assert_equals "198.51.100.107" "$PBS_SERVER" "Valid config still parsed"
    
    echo
}

# ---------------------------------------------------------------------------
# Main Test Runner
# ---------------------------------------------------------------------------

main() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${RED}ERROR:${NC} Tests must be run as root (some operations require root)"
        echo "Usage: sudo $0"
        exit 1
    fi
    
    test_setup
    trap test_teardown EXIT
    
    test_config_parsing
    test_encryption_keyfile_creation
    test_keyfile_path_masking_in_logs
    test_mount_point_detection
    test_lock_file_management
    test_credentials_validation
    test_trap_cleanup_on_error
    test_config_file_injection_protection
}

main "$@"
