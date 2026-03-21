#!/bin/bash
# =============================================================================
# Plan B: Live Migration — Docker Volumes to NFS Persistence
# =============================================================================
#
# Migrates a running vm_docker-pool server to use NFS-backed Docker volumes
# WITHOUT data loss. This script is meant for ONE-TIME migration of an
# existing server to match the fresh-install architecture (Plan A).
#
# What this script does:
#   Phase 1: Setup NFS export on PVE host (no downtime)
#   Phase 2: Install NFS client + initial rsync on VM (no downtime)
#   Phase 3: Stop containers, final sync, mount switch (brief downtime ~2-5 min)
#   Phase 4: Update Portainer compose to named volume
#   Phase 5: Start all containers, verify
#
# Prerequisites:
#   - SSH access to PVE host as root (via ansible key)
#   - SSH access to Docker VM as ansible (sudo)
#   - /rpool/datastore/docker-pool/ ZFS dataset exists on PVE host
#
# Usage:
#   ./scripts/migrate_to_nfs_volumes.sh
#
# Environment variables (optional):
#   PVE_HOST     — PVE host IP (default: 198.51.100.1)
#   VM_HOST      — Docker VM IP (default: 198.51.100.200)
#   SSH_KEY      — SSH private key path (default: ~/.ssh/ansible)
#   NFS_PATH     — NFS export path on PVE (default: /rpool/datastore/docker-pool/volumes)
#   NFS_SUBNET   — NFS allowed subnet (default: 198.51.100.0/24)
#   DRY_RUN      — Set to "true" to only show what would be done
#
# Last Updated: March 2026
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

PVE_HOST="${PVE_HOST:-198.51.100.1}"
VM_HOST="${VM_HOST:-198.51.100.200}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/ansible}"
NFS_PATH="${NFS_PATH:-/rpool/datastore/docker-pool/volumes}"
NFS_SUBNET="${NFS_SUBNET:-198.51.100.0/24}"
DRY_RUN="${DRY_RUN:-false}"

SSH_PVE="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"
SSH_VM="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Temporary NFS mount point on VM (used during migration only)
TMP_NFS_MOUNT="/mnt/docker-volumes-nfs"

# =============================================================================
# Logging
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $(date '+%H:%M:%S') $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*"; }
log_phase() { echo -e "\n${GREEN}========================================${NC}"; echo -e "${GREEN} Phase $1: $2${NC}"; echo -e "${GREEN}========================================${NC}\n"; }

run_pve() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] PVE: $*"
  else
    $SSH_PVE root@"$PVE_HOST" "$@"
  fi
}

run_vm() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] VM: $*"
  else
    $SSH_VM ansible@"$VM_HOST" "sudo bash -c '$*'"
  fi
}

run_vm_nosudo() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] VM: $*"
  else
    $SSH_VM ansible@"$VM_HOST" "$@"
  fi
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

preflight_checks() {
  log_info "Running pre-flight checks..."

  # Check SSH key exists
  if [[ ! -f "$SSH_KEY" ]]; then
    log_error "SSH key not found: $SSH_KEY"
    exit 1
  fi

  # Check PVE host reachable
  log_info "Testing PVE host connectivity ($PVE_HOST)..."
  if ! $SSH_PVE root@"$PVE_HOST" "echo 'PVE OK'" &>/dev/null; then
    log_error "Cannot SSH to PVE host root@$PVE_HOST"
    exit 1
  fi
  log_ok "PVE host reachable"

  # Check VM reachable
  log_info "Testing VM connectivity ($VM_HOST)..."
  if ! $SSH_VM ansible@"$VM_HOST" "echo 'VM OK'" &>/dev/null; then
    log_error "Cannot SSH to VM ansible@$VM_HOST"
    exit 1
  fi
  log_ok "VM reachable"

  # Check ZFS dataset exists on PVE
  log_info "Checking ZFS dataset on PVE..."
  if ! $SSH_PVE root@"$PVE_HOST" "zfs list rpool/datastore/docker-pool" &>/dev/null; then
    log_error "ZFS dataset rpool/datastore/docker-pool not found on PVE host"
    log_info "Create it with: ssh root@$PVE_HOST 'zfs create rpool/datastore/docker-pool'"
    exit 1
  fi
  log_ok "ZFS dataset exists"

  # Check Docker is running on VM
  log_info "Checking Docker on VM..."
  if ! $SSH_VM ansible@"$VM_HOST" "sudo docker info" &>/dev/null; then
    log_error "Docker is not running on $VM_HOST"
    exit 1
  fi
  log_ok "Docker is running"

  # Show current Docker volumes
  log_info "Current Docker named volumes on VM:"
  $SSH_VM ansible@"$VM_HOST" "sudo docker volume ls --format 'table {{.Name}}\t{{.Driver}}'"

  # Show current disk usage
  log_info "Docker volumes disk usage:"
  $SSH_VM ansible@"$VM_HOST" "sudo du -sh /var/lib/docker/volumes/ 2>/dev/null || echo 'N/A'"

  echo ""
}

# =============================================================================
# Phase 1: PVE Host NFS Setup
# =============================================================================

phase1_pve_nfs_setup() {
  log_phase "1" "PVE Host NFS Setup (no downtime)"

  # Create volumes directory
  log_info "Creating NFS export directory: $NFS_PATH"
  run_pve "mkdir -p '$NFS_PATH' && chmod 755 '$NFS_PATH'"
  log_ok "Directory created"

  # Install NFS server if needed
  log_info "Ensuring NFS server is installed on PVE..."
  run_pve "dpkg -l | grep -q nfs-kernel-server || (apt-get update -qq && apt-get install -y -qq nfs-kernel-server)"
  run_pve "systemctl enable --now nfs-kernel-server"
  log_ok "NFS server ready"

  # Add NFS export (idempotent)
  local EXPORT_LINE="$NFS_PATH $NFS_SUBNET(rw,sync,no_subtree_check,no_root_squash)"
  log_info "Configuring NFS export..."
  run_pve "grep -qF '$NFS_PATH' /etc/exports || echo '$EXPORT_LINE' >> /etc/exports"
  run_pve "exportfs -ra"
  log_ok "NFS export configured: $EXPORT_LINE"

  # Verify
  if [[ "$DRY_RUN" != "true" ]]; then
    log_info "Verifying NFS export..."
    $SSH_PVE root@"$PVE_HOST" "showmount -e localhost | grep docker-pool"
    log_ok "NFS export verified"
  fi
}

# =============================================================================
# Phase 2: VM NFS Client + Initial Rsync
# =============================================================================

phase2_vm_nfs_client() {
  log_phase "2" "VM NFS Client + Initial Rsync (no downtime)"

  # Install NFS client
  log_info "Installing NFS client on VM..."
  run_vm "apt-get update -qq && apt-get install -y -qq nfs-common"
  log_ok "NFS client installed"

  # Create temporary mount point
  log_info "Creating temporary NFS mount point..."
  run_vm "mkdir -p '$TMP_NFS_MOUNT'"

  # Mount NFS temporarily
  log_info "Mounting NFS export temporarily at $TMP_NFS_MOUNT..."
  run_vm "mountpoint -q '$TMP_NFS_MOUNT' || mount -t nfs4 '$PVE_HOST:$NFS_PATH' '$TMP_NFS_MOUNT' -o defaults,noatime"
  log_ok "NFS mounted temporarily"

  # Initial rsync (containers still running — this is a pre-copy)
  log_info "Initial rsync of Docker volumes (containers still running)..."
  log_info "This may take a while depending on volume sizes..."
  run_vm "rsync -av --info=progress2 /var/lib/docker/volumes/ '$TMP_NFS_MOUNT/'"
  log_ok "Initial rsync complete"

  # Copy Portainer data (from bind mount path)
  if $SSH_VM ansible@"$VM_HOST" "sudo test -d /opt/portainer/data" 2>/dev/null; then
    log_info "Pre-copying Portainer data to NFS..."
    run_vm "mkdir -p '$TMP_NFS_MOUNT/portainer_data/_data' && rsync -av /opt/portainer/data/ '$TMP_NFS_MOUNT/portainer_data/_data/'"
    log_ok "Portainer data pre-copied"
  fi
}

# =============================================================================
# Phase 3: Stop Containers + Final Sync + Mount Switch
# =============================================================================

phase3_mount_switch() {
  log_phase "3" "Stop Containers + Final Sync + Mount Switch (DOWNTIME STARTS)"

  log_warn ">>> SERVICE DOWNTIME BEGINS <<<"
  log_warn "All Docker containers will be stopped now."
  echo ""

  if [[ "$DRY_RUN" != "true" ]]; then
    read -rp "Continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
      log_warn "Aborted by user. Cleaning up temporary mount..."
      run_vm "umount '$TMP_NFS_MOUNT' 2>/dev/null; rmdir '$TMP_NFS_MOUNT' 2>/dev/null" || true
      exit 0
    fi
  fi

  # Stop Docker service (stops ALL containers cleanly)
  log_info "Stopping Docker service..."
  run_vm "systemctl stop docker docker.socket containerd"
  log_ok "Docker stopped"

  # Final rsync (delta only, fast since pre-copy was done)
  log_info "Final rsync (delta copy)..."
  run_vm "rsync -av --delete /var/lib/docker/volumes/ '$TMP_NFS_MOUNT/'"
  log_ok "Final rsync complete"

  # Final Portainer sync
  if $SSH_VM ansible@"$VM_HOST" "sudo test -d /opt/portainer/data" 2>/dev/null; then
    log_info "Final Portainer data sync..."
    run_vm "rsync -av --delete /opt/portainer/data/ '$TMP_NFS_MOUNT/portainer_data/_data/'"
    log_ok "Portainer data synced"
  fi

  # Unmount temporary NFS
  log_info "Unmounting temporary NFS mount..."
  run_vm "umount '$TMP_NFS_MOUNT' && rmdir '$TMP_NFS_MOUNT'"
  log_ok "Temporary mount removed"

  # Move old volumes directory out of the way
  log_info "Moving old /var/lib/docker/volumes to /var/lib/docker/volumes.old..."
  run_vm "mv /var/lib/docker/volumes /var/lib/docker/volumes.old"
  run_vm "mkdir -p /var/lib/docker/volumes"
  log_ok "Old volumes directory backed up"

  # Create permanent fstab entry using ansible.posix.mount-compatible format
  log_info "Adding NFS mount to /etc/fstab..."
  local FSTAB_ENTRY="$PVE_HOST:$NFS_PATH /var/lib/docker/volumes nfs4 defaults,_netdev,noatime 0 0"
  run_vm "grep -qF '/var/lib/docker/volumes' /etc/fstab || echo '$FSTAB_ENTRY' >> /etc/fstab"
  log_ok "fstab entry added"

  # Mount the NFS volume
  log_info "Mounting NFS at /var/lib/docker/volumes..."
  run_vm "mount /var/lib/docker/volumes"
  log_ok "NFS mounted permanently"

  # Create systemd override for Docker to depend on NFS mount
  log_info "Creating Docker systemd override..."
  run_vm "mkdir -p /etc/systemd/system/docker.service.d"
  run_vm "cat > /etc/systemd/system/docker.service.d/nfs-volumes.conf << 'OVERRIDE'
# Managed by migration script - ensure Docker starts after NFS volumes mount
[Unit]
Requires=var-lib-docker-volumes.mount
After=var-lib-docker-volumes.mount
OVERRIDE"
  run_vm "systemctl daemon-reload"
  log_ok "Docker systemd override created"

  # Start Docker
  log_info "Starting Docker service..."
  run_vm "systemctl start containerd docker"
  log_ok "Docker started"

  log_ok ">>> MOUNT SWITCH COMPLETE <<<"
}

# =============================================================================
# Phase 4: Update Portainer Compose to Named Volume
# =============================================================================

phase4_update_portainer() {
  log_phase "4" "Update Portainer to Named Volume"

  local COMPOSE_PATH="/opt/portainer/docker-compose.yml"

  # Check if Portainer compose exists
  if ! $SSH_VM ansible@"$VM_HOST" "sudo test -f $COMPOSE_PATH" 2>/dev/null; then
    log_warn "Portainer compose not found at $COMPOSE_PATH, skipping."
    return
  fi

  # Backup current compose
  log_info "Backing up current Portainer compose..."
  run_vm "cp '$COMPOSE_PATH' '${COMPOSE_PATH}.bak.$(date +%Y%m%d%H%M%S)'"

  # Write new compose file with named volume
  log_info "Updating Portainer compose to use named volume..."
  run_vm "cat > '$COMPOSE_PATH' << 'COMPOSE'
# Portainer CE - Docker Compose Configuration
# Updated by migration script to use named volume (NFS-backed)
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    security_opt:
      - no-new-privileges:true
    ports:
      - \"9443:9443\"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    healthcheck:
      disable: true
    labels:
      - \"traefik.enable=false\"
      - \"com.centurylinklabs.watchtower.enable=false\"

volumes:
  portainer_data:
    name: portainer_data

networks:
  default:
    driver: bridge
COMPOSE"
  log_ok "Portainer compose updated"

  # Remove old portainer container and start new one
  log_info "Restarting Portainer with named volume..."
  run_vm "cd /opt/portainer && docker compose down 2>/dev/null; docker compose up -d"
  log_ok "Portainer restarted with named volume"
}

# =============================================================================
# Phase 5: Restart All Services + Verify
# =============================================================================

phase5_verify() {
  log_phase "5" "Verification"

  # Verify NFS mount
  log_info "Verifying NFS mount..."
  if [[ "$DRY_RUN" != "true" ]]; then
    $SSH_VM ansible@"$VM_HOST" "sudo mount | grep '/var/lib/docker/volumes'"
    log_ok "NFS mount active"
  fi

  # Verify Docker is running
  log_info "Verifying Docker..."
  if [[ "$DRY_RUN" != "true" ]]; then
    $SSH_VM ansible@"$VM_HOST" "sudo docker info --format '{{.ServerVersion}}'"
    log_ok "Docker running"
  fi

  # List running containers
  log_info "Running containers:"
  if [[ "$DRY_RUN" != "true" ]]; then
    $SSH_VM ansible@"$VM_HOST" "sudo docker ps --format 'table {{.Names}}\t{{.Status}}'"
  fi

  # List Docker volumes on NFS
  log_info "Docker volumes (now on NFS):"
  if [[ "$DRY_RUN" != "true" ]]; then
    $SSH_VM ansible@"$VM_HOST" "sudo docker volume ls --format 'table {{.Name}}\t{{.Driver}}'"
  fi

  # Verify data on PVE host
  log_info "Verifying data on PVE host ($NFS_PATH):"
  if [[ "$DRY_RUN" != "true" ]]; then
    $SSH_PVE root@"$PVE_HOST" "ls -la '$NFS_PATH/' | head -20"
  fi

  echo ""
  log_ok "========================================="
  log_ok " Migration Complete!"
  log_ok "========================================="
  log_ok ""
  log_ok " NFS mount: $PVE_HOST:$NFS_PATH -> /var/lib/docker/volumes"
  log_ok " All Docker named volumes now persist on PVE ZFS storage."
  log_ok " PBS backup will cover /rpool/datastore/docker-pool/ automatically."
  log_ok ""
  log_warn " Old volumes backed up at /var/lib/docker/volumes.old on VM."
  log_warn " After 24h stable operation, remove with:"
  log_warn "   ssh ansible@$VM_HOST 'sudo rm -rf /var/lib/docker/volumes.old'"
  log_ok ""
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo ""
  echo "============================================="
  echo " VM Docker-Pool: NFS Volumes Migration"
  echo "============================================="
  echo ""
  echo " PVE Host:    $PVE_HOST"
  echo " Docker VM:   $VM_HOST"
  echo " NFS Path:    $NFS_PATH"
  echo " NFS Subnet:  $NFS_SUBNET"
  echo " Dry Run:     $DRY_RUN"
  echo ""

  if [[ "$DRY_RUN" != "true" ]]; then
    read -rp "Start migration? (yes/no): " start_confirm
    if [[ "$start_confirm" != "yes" ]]; then
      log_warn "Migration cancelled."
      exit 0
    fi
  fi

  preflight_checks
  phase1_pve_nfs_setup
  phase2_vm_nfs_client
  phase3_mount_switch
  phase4_update_portainer
  phase5_verify
}

# Run
main "$@"
