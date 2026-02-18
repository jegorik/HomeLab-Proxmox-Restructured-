#!/usr/bin/env bash
# =============================================================================
# Vault Functions - Promtail Remote Install
# =============================================================================
# Authenticates to HashiCorp Vault via userpass method and retrieves the
# Loki basic-auth password from the KV secrets engine.
#
# The secret must contain at minimum the 'password' field.
# 'url' and 'username' are optional — they can also be set in deploy.conf.
#
# Example — store only password (url comes from deploy.conf / env):
#   vault kv put secrets/proxmox/promtail \
#     password="<your-loki-password>"
#
# Example — store all fields:
#   vault kv put secrets/proxmox/promtail \
#     url="https://loki.example.com" \
#     username="promtail" \
#     password="<your-loki-password>"
#
# Required env / config:
#   VAULT_ADDR      - Vault server URL
#   VAULT_USERNAME  - Vault userpass username
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_VAULT_SH_LOADED:-}" ]] && return 0
_VAULT_SH_LOADED=1

# Default secret path — override via PROMTAIL_VAULT_SECRET_PATH env var
# or vault_secret_path= in deploy.conf
PROMTAIL_VAULT_SECRET_PATH="${PROMTAIL_VAULT_SECRET_PATH:-secrets/proxmox/promtail}"

# ---------------------------------------------------------------------------
# Read a variable from the optional config file (deploy.conf)
# ---------------------------------------------------------------------------
_conf_read() {
    local key="$1"
    local default="${2:-}"
    local conf="${SCRIPT_DIR}/deploy.conf"

    if [[ -f "${conf}" ]]; then
        local val
        val=$(grep -E "^${key}\\s*=" "${conf}" 2>/dev/null \
              | head -1 \
              | sed 's/[^=]*=\s*//' \
              | tr -d '"'"'" \
              | tr -d '\r')
        [[ -n "${val}" ]] && { echo "${val}"; return 0; }
    fi
    echo "${default}"
}

# ---------------------------------------------------------------------------
# Check / prompt for Vault connection parameters
# ---------------------------------------------------------------------------
vault_check_configuration() {
    log_info "Configuring Vault connection..."

    # VAULT_ADDR: env → config file → prompt
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        VAULT_ADDR=$(_conf_read "vault_addr")
    fi
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        log_warning "VAULT_ADDR not set"
        echo -n "  Enter Vault address [https://vault.example.com:8200]: "
        read -r VAULT_ADDR
        [[ -z "${VAULT_ADDR}" ]] && { log_error "VAULT_ADDR is required"; return 1; }
    fi
    export VAULT_ADDR
    log_success "VAULT_ADDR=${VAULT_ADDR}"

    # VAULT_USERNAME: env → config file → prompt
    if [[ -z "${VAULT_USERNAME:-}" ]]; then
        VAULT_USERNAME=$(_conf_read "vault_username")
    fi
    if [[ -z "${VAULT_USERNAME:-}" ]]; then
        log_warning "VAULT_USERNAME not set"
        echo -n "  Enter Vault username: "
        read -r VAULT_USERNAME
        [[ -z "${VAULT_USERNAME}" ]] && { log_error "VAULT_USERNAME is required"; return 1; }
    fi
    export VAULT_USERNAME
    log_success "VAULT_USERNAME=${VAULT_USERNAME}"

    # Secret path: env → config file → default
    if [[ -z "${PROMTAIL_VAULT_SECRET_PATH:-}" ]]; then
        PROMTAIL_VAULT_SECRET_PATH=$(_conf_read "vault_secret_path" "secrets/proxmox/promtail")
    fi
    export PROMTAIL_VAULT_SECRET_PATH
    log_success "VAULT_SECRET_PATH=${PROMTAIL_VAULT_SECRET_PATH}"

    return 0
}

# ---------------------------------------------------------------------------
# Check Vault connectivity and seal status
# ---------------------------------------------------------------------------
vault_check_connectivity() {
    log_info "Checking Vault connectivity at ${VAULT_ADDR}..."

    if ! vault status &>/dev/null; then
        log_error "Cannot connect to Vault at ${VAULT_ADDR}"
        log_info "Check that VAULT_ADDR is correct and Vault is running"
        return 1
    fi

    local sealed
    sealed=$(vault status -format=json 2>/dev/null | jq -r '.sealed')
    if [[ "${sealed}" == "true" ]]; then
        log_error "Vault is sealed. Run: vault operator unseal"
        return 1
    fi

    log_success "Vault is reachable and unsealed"
    return 0
}

# ---------------------------------------------------------------------------
# Authenticate with Vault (userpass). Reuses existing valid token.
# ---------------------------------------------------------------------------
vault_authenticate() {
    log_info "Checking Vault authentication..."

    # Reuse existing valid token
    if vault token lookup &>/dev/null; then
        local display_name ttl
        display_name=$(vault token lookup -format=json | jq -r '.data.display_name')
        ttl=$(vault token lookup -format=json | jq -r '.data.ttl')
        log_success "Already authenticated as '${display_name}' (TTL: ${ttl}s)"
        VAULT_TOKEN=$(vault token lookup -format=json | jq -r '.data.id')
        export VAULT_TOKEN
        return 0
    fi

    log_info "Logging in as ${VAULT_USERNAME}..."
    echo -n "  Enter Vault password: "
    read -r -s VAULT_PASSWORD
    echo ""

    local vault_token
    if ! vault_token=$(echo "${VAULT_PASSWORD}" | \
            vault login -method=userpass username="${VAULT_USERNAME}" password=- \
            -token-only -format=json 2>/dev/null | jq -r '.auth.client_token // .'); then
        log_error "Authentication failed"
        return 1
    fi

    # Fallback: token-only flag returns raw token string, not JSON
    if [[ "${vault_token}" == "{"* ]]; then
        vault_token=$(echo "${vault_token}" | jq -r '.auth.client_token')
    fi

    if [[ -z "${vault_token}" || "${vault_token}" == "null" ]]; then
        log_error "Authentication failed — empty token"
        return 1
    fi

    export VAULT_TOKEN="${vault_token}"
    log_success "Authenticated successfully"
    return 0
}

# ---------------------------------------------------------------------------
# Retrieve Loki credentials from Vault KV and export as env vars.
#
# The secret MUST contain 'password'.
# 'url' and 'username' are optional — if absent, they fall back to
# PROMTAIL_LOKI_URL / PROMTAIL_LOKI_USER env vars or deploy.conf values.
#
# Uses 'vault read' (raw API path) so that the caller controls the exact
# path without the kv-v2 implicit /data/ rewrite done by 'vault kv get'.
# This matches paths visible via 'vault read secrets/proxmox/data/promtail'.
# ---------------------------------------------------------------------------
vault_get_loki_credentials() {
    log_info "Fetching Loki credentials from Vault (${PROMTAIL_VAULT_SECRET_PATH})..."

    local secret_json
    # vault read accepts the raw path. For KV v2 the mount is e.g. 'secrets/proxmox'
    # and vault read secrets/proxmox/data/promtail works, but the friendlier path
    # secrets/proxmox/promtail also works because vault kv get adds /data/ automatically.
    # We use vault kv get here — it handles both v1 and v2 mounts transparently.
    if ! secret_json=$(vault kv get -format=json "${PROMTAIL_VAULT_SECRET_PATH}" 2>&1); then
        # vault kv get failed — try direct vault read (path already contains /data/)
        if ! secret_json=$(vault read -format=json "${PROMTAIL_VAULT_SECRET_PATH}" 2>&1); then
            log_error "Failed to read secret at '${PROMTAIL_VAULT_SECRET_PATH}'"
            log_error "${secret_json}"
            log_info "Verify the path with:"
            log_info "  vault read -format=json ${PROMTAIL_VAULT_SECRET_PATH}"
            log_info "Or update vault_secret_path in deploy.conf to the correct path."
            log_info "Minimum required secret content:"
            log_info "  vault kv put ${PROMTAIL_VAULT_SECRET_PATH} password=\"<loki-password>\""
            return 1
        fi
    fi

    # KV v2 wraps data under .data.data; KV v1 / vault read uses .data directly
    local data_key=".data.data"
    if ! echo "${secret_json}" | jq -e '.data.data' &>/dev/null; then
        data_key=".data"
    fi

    local loki_url loki_user loki_password
    loki_url=$(echo      "${secret_json}" | jq -r "${data_key}.url      // empty")
    loki_user=$(echo     "${secret_json}" | jq -r "${data_key}.username // empty")
    loki_password=$(echo "${secret_json}" | jq -r "${data_key}.password // empty")

    # password is the only mandatory field in the secret
    if [[ -z "${loki_password}" ]]; then
        log_error "Key 'password' not found in secret '${PROMTAIL_VAULT_SECRET_PATH}'"
        log_info "Add it with: vault kv put ${PROMTAIL_VAULT_SECRET_PATH} password=\"<loki-password>\""
        return 1
    fi
    export PROMTAIL_LOKI_PASSWORD="${loki_password}"
    log_success "Loki password retrieved from Vault (not logged)"

    # url: Vault secret → deploy.conf → env var → prompt
    if [[ -z "${PROMTAIL_LOKI_URL:-}" ]]; then
        if [[ -n "${loki_url}" ]]; then
            export PROMTAIL_LOKI_URL="${loki_url}"
            log_success "Loki URL from Vault: ${PROMTAIL_LOKI_URL}"
        else
            PROMTAIL_LOKI_URL=$(_conf_read "loki_url")
            if [[ -z "${PROMTAIL_LOKI_URL:-}" ]]; then
                log_warning "Loki URL not found in Vault secret or deploy.conf"
                echo -n "  Enter Loki URL [https://loki.example.com]: "
                read -r PROMTAIL_LOKI_URL
                [[ -z "${PROMTAIL_LOKI_URL}" ]] && { log_error "Loki URL is required"; return 1; }
            fi
            export PROMTAIL_LOKI_URL
            log_success "Loki URL: ${PROMTAIL_LOKI_URL}"
        fi
    else
        log_success "Loki URL (env/CLI): ${PROMTAIL_LOKI_URL}"
    fi

    # username: Vault secret → deploy.conf → default 'promtail'
    if [[ -z "${PROMTAIL_LOKI_USER:-}" ]]; then
        if [[ -n "${loki_user}" ]]; then
            export PROMTAIL_LOKI_USER="${loki_user}"
        else
            PROMTAIL_LOKI_USER=$(_conf_read "loki_username" "promtail")
            export PROMTAIL_LOKI_USER
        fi
    fi
    log_success "Loki username: ${PROMTAIL_LOKI_USER}"

    return 0
}

# ---------------------------------------------------------------------------
# Master initialization: configure → connect → auth → fetch secret
# ---------------------------------------------------------------------------
vault_initialize() {
    log_header "Vault Authentication"

    vault_check_configuration  || return 1
    vault_check_connectivity   || return 1
    vault_authenticate         || return 1
    vault_get_loki_credentials || return 1

    log_success "Vault initialization complete"
    return 0
}
