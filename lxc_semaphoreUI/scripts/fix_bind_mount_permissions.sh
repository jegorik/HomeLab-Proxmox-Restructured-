#!/bin/bash
set -e

# =============================================================================
# Fix Bind Mount Permissions for Unprivileged LXC
# =============================================================================
# This script is intended to be run on the Proxmox Host.
# It ensures that the bind mount directory exists and has the correct
# ownership for an unprivileged LXC container (using UID/GID mapping).
#
# Logic:
# 1. Host Root (0) maps to Container Root (0) -> Host 100000
# 2. Container Service User (UID) -> Host 100000 + UID
#
# Arguments:
#   1. path: Path to the directory on the host (e.g., /rpool/dist/vault)
#   2. uid: Target UID inside the container (e.g., 100 for vault user)
#   3. gid: Target GID inside the container (e.g., 100 for vault group)
#   4. root_uid_map: Base ID mapping (default: 100000)
# =============================================================================

MOUNT_PATH="${1}"
TARGET_UID="${2}"
TARGET_GID="${3}"
ROOT_MAP="${4:-100000}"

if [[ -z "${MOUNT_PATH}" || -z "${TARGET_UID}" ]]; then
    echo "Usage: $0 <path> <uid> [gid] [root_map]"
    exit 1
fi

if [[ ! "${MOUNT_PATH}" =~ ^/rpool/datastore/.* ]]; then
    echo "ERROR: Path must be under /rpool/datastore/ for safety."
    echo "Received: ${MOUNT_PATH}"
    exit 1
fi

# Calculate host ID
HOST_UID=$((ROOT_MAP + TARGET_UID))
HOST_GID=$((ROOT_MAP + TARGET_GID))

echo "checking permissions for ${MOUNT_PATH}..."
echo "Target Host ownership: ${HOST_UID}:${HOST_GID}"

# Ensure directory exists
if [[ ! -d "${MOUNT_PATH}" ]]; then
    echo "Creating directory: ${MOUNT_PATH}"
    mkdir -p "${MOUNT_PATH}"
    chown "${HOST_UID}:${HOST_GID}" "${MOUNT_PATH}"
    chmod 755 "${MOUNT_PATH}"
    echo "Directory created and permissions set."
    exit 0
fi

# Check emptiness
if [[ -z "$(ls -A "${MOUNT_PATH}")" ]]; then
    echo "Directory is empty. Setting permissions..."
    chown "${HOST_UID}:${HOST_GID}" "${MOUNT_PATH}"
    chmod 755 "${MOUNT_PATH}"
else
    echo "Directory contains data."
    # Check ownership of the directory itself
    CURRENT_UID=$(stat -c '%u' "${MOUNT_PATH}")
    
    if [[ "${CURRENT_UID}" -eq "${HOST_UID}" ]]; then
        echo "Ownership matches target (${HOST_UID}). Assuming correct."
    else
        echo "Ownership mismatch (Current: ${CURRENT_UID}, Expected: ${HOST_UID})."
        echo "Updating ownership for existing data..."
        chown -R "${HOST_UID}:${HOST_GID}" "${MOUNT_PATH}"
    fi
fi

echo "Done."
