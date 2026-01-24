#!/bin/bash
set -e  # Exit on any error

# =============================================================================
# Ansible User Setup Script
# =============================================================================
# Usage: ./setup_ansible_user.sh [enabled] [username] [shell] [sudo_enabled] [sudo_commands] [groups]
#
# Arguments:
#   1. enabled: "true" or "false"
#   2. username: Name of the user to create
#   3. shell: Shell for the user (e.g., /bin/bash)
#   4. sudo_enabled: "true" or "false"
#   5. sudo_commands: Comma-separated list of allowed sudo commands (or empty for ALL)
#   6. groups: Comma-separated list of additional groups
#
# Environment Variables (Required):
#   ANSIBLE_SSH_KEY: Public SSH key for the user
# =============================================================================

ENABLE_USER="${1:-true}"
USER_NAME="${2:-ansible}"
USER_SHELL="${3:-/bin/bash}"
SUDO_ENABLED="${4:-true}"
SUDO_COMMANDS="${5:-}"
USER_GROUPS="${6:-}"

echo "=== Setting up Ansible user ==="

# Wait for container to fully boot
echo "Waiting for system to be ready..."
sleep 10

# Update package lists
apt-get update -qq && apt-get upgrade -qq

# Install sudo if not present
apt-get install -y -qq sudo

if [[ "${ENABLE_USER}" != "true" ]]; then
  echo "Ansible user creation disabled"
  exit 0
fi

echo ""
echo "Creating Ansible user: ${USER_NAME}"

# Create Ansible user if it doesn't exist
if ! id -u "${USER_NAME}" > /dev/null 2>&1; then
  useradd -m -s "${USER_SHELL}" "${USER_NAME}"
  echo "✓ User '${USER_NAME}' created"
else
  echo "✓ User '${USER_NAME}' already exists"
fi

# Create .ssh directory and set permissions
mkdir -p "/home/${USER_NAME}/.ssh"
chmod 700 "/home/${USER_NAME}/.ssh"

# Add SSH public key
if [[ -n "${ANSIBLE_SSH_KEY}" ]]; then
  echo "${ANSIBLE_SSH_KEY}" > "/home/${USER_NAME}/.ssh/authorized_keys"
  chmod 600 "/home/${USER_NAME}/.ssh/authorized_keys"
  chown -R "${USER_NAME}:${USER_NAME}" "/home/${USER_NAME}/.ssh"
else
  echo "WARNING: No SSH key provided for ${USER_NAME}"
fi

# Configure sudo access
if [[ "${SUDO_ENABLED}" == "true" ]]; then
  usermod -aG sudo "${USER_NAME}"
  mkdir -p /etc/sudoers.d

  if [[ -n "${SUDO_COMMANDS}" ]]; then
    # Limited sudo commands
    cat > "/etc/sudoers.d/${USER_NAME}" <<SUDOERS_EOF
# Ansible user sudo configuration - managed by Terraform
${USER_NAME} ALL=(ALL) NOPASSWD: ${SUDO_COMMANDS}
SUDOERS_EOF
  else
    # Full sudo access without password
    cat > "/etc/sudoers.d/${USER_NAME}" <<SUDOERS_EOF
# Ansible user sudo configuration - managed by Terraform
${USER_NAME} ALL=(ALL) NOPASSWD:ALL
SUDOERS_EOF
  fi

  chmod 440 "/etc/sudoers.d/${USER_NAME}"
  visudo -c -f "/etc/sudoers.d/${USER_NAME}"
  echo "✓ Sudo access configured"
else
  echo "# Sudo access not enabled"
fi

# Add to additional groups
if [[ -n "${USER_GROUPS}" ]]; then
  usermod -aG "${USER_GROUPS}" "${USER_NAME}"
  echo "✓ Added to groups: ${USER_GROUPS}"
fi

# Get IP address for display
CONTAINER_IP=$(hostname -I | cut -d' ' -f1)

echo ""
echo "✓ Ansible user '${USER_NAME}' setup complete"
echo "SSH access: ssh ${USER_NAME}@${CONTAINER_IP}"
