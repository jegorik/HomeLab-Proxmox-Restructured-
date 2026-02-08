# =============================================================================
# VM OpenSUSE Tumbleweed - Cloud-Init Customization
# =============================================================================

locals {
  # Cloud-Init User Data Configuration
  user_data = templatefile("${path.module}/templates/${var.cloudinit_data_file_name}", {
    hostname              = var.vm_hostname
    site_name             = var.site_name
    root_ssh_key          = trimspace(data.vault_generic_secret.root_ssh_public_key.data["key"])
    vm_root_password      = terraform_data.password_keeper.input
    vm_username           = var.vm_username
    ansible_username      = var.ansible_user_name
    ansible_ssh_key       = trimspace(data.vault_generic_secret.ansible_ssh_public_key.data["key"])
    target_user_uid       = var.target_user_uid
    virtiofs_home_enabled = var.virtiofs_home_enabled
    virtiofs_home_mapping = var.virtiofs_home_mapping
    virtiofs_etc_enabled  = var.virtiofs_etc_enabled
    virtiofs_etc_mapping  = var.virtiofs_etc_mapping
    # Network configuration for static IP
    use_dhcp       = var.vm_use_dhcp
    vm_ip_address  = var.vm_ip_address
    vm_gateway     = var.vm_gateway
    vm_dns_servers = "${join(";", var.vm_dns_servers)};"
  })
}

# =============================================================================
# Trigger Resource for Cloud-Init Configuration Changes
# =============================================================================
# This resource uses the terraform_data resource to track changes in cloud-init
# configuration variables. When any tracked variable changes, it triggers
# replacement of the cloud-init snippet file in Proxmox storage.
#
# Tracked Variables:
# - root_username: Name of the root user to create
# - ansible_key: SSH public key for Ansible service account
# - root_key: SSH public key for root user
# - hostname: VM hostname (affects cloud-init identity)
#
# Why This Matters:
# Without this trigger, changing SSH keys or usernames would not update the
# cloud-init snippet, causing new VMs to use old configuration. The trigger
# ensures the snippet is always synchronized with current variables.
#
# Usage Pattern (Advanced):
# This pattern is useful for any configuration file that needs to be
# regenerated when input variables change, especially for immutable
# infrastructure where file content must match declared state.

resource "terraform_data" "cloud_init_trigger" {
  count = var.cloudinit_enabled ? 1 : 0

  input = {
    root_username = var.vm_username
    root_key      = data.vault_generic_secret.root_ssh_public_key.data["key"]
    hostname      = var.vm_hostname
  }
}

# -----------------------------------------------------------------------------
# Upload Cloud-Init Snippet to Proxmox
# -----------------------------------------------------------------------------
# This resource uploads the generated user-data to Proxmox storage
# so it can be referenced by the VM resource.

resource "proxmox_virtual_environment_file" "cloud_init_user_config" {
  count        = var.cloudinit_enabled ? 1 : 0
  content_type = var.cloudinit_content_type   # Default "snippets"
  datastore_id = var.vm_cloud_image_datastore # Snippets usually on local
  node_name    = data.vault_generic_secret.proxmox_node_name.data["node_name"]

  source_raw {
    data      = local.user_data
    file_name = "user-data-${var.vm_hostname}.yaml"
  }

  # Recreate snippet file when trigger resource detects changes
  # This ensures cloud-init configuration stays synchronized with variables
  lifecycle {
    replace_triggered_by = [terraform_data.cloud_init_trigger]
  }
}
