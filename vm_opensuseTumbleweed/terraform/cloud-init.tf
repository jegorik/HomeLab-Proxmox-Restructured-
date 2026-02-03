# =============================================================================
# VM OpenSUSE Tumbleweed - Cloud-Init Customization
# =============================================================================

locals {
  # Cloud-Init User Data Configuration
  user_data = templatefile("${path.module}/${var.cloudinit_data_file_name}", {
    hostname           = var.vm_hostname
    site_name          = var.site_name
    root_ssh_key       = trimspace(data.vault_generic_secret.root_ssh_public_key.data["key"])
    ansible_user_name  = var.ansible_user_name
    ansible_user_shell = var.ansible_user_shell
    ansible_ssh_key    = trimspace(data.vault_generic_secret.ansible_ssh_public_key.data["key"])
  })
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
    replace_triggered_by = [terraform_data.cloud_init_trigger[count.index]]
  }
}
