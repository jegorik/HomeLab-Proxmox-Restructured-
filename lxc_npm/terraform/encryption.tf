# =============================================================================
# OpenTofu State File Encryption Configuration - Vault Transit Engine
# =============================================================================
# This file configures state file encryption using HashiCorp Vault's Transit
# Secrets Engine for centralized encryption key management and cryptographic
# operations as a service.
#
# Security Features:
# - Centralized key management via Vault Transit engine
# - Keys never leave Vault (encryption/decryption via API)
# - Automatic key versioning and rotation support
# - Full audit trail of all cryptographic operations
# - AES-256-GCM authenticated encryption
# - Policy-based access control
#
# Prerequisites:
# 1. Enable Transit secrets engine in Vault:
#    vault secrets enable transit
#
# 2. Create encryption key in Vault:
#    vault write -f transit/keys/tofu-state-encryption
#
# 3. Update Vault policy to allow OpenTofu access:
#    path "transit/encrypt/tofu-state-encryption" {
#      capabilities = ["update"]
#    }
#    path "transit/decrypt/tofu-state-encryption" {
#      capabilities = ["update"]
#    }
#
# Last Updated: January 2026
# =============================================================================

terraform {
  encryption {
    # -------------------------------------------------------------------------
    # OpenBao Key Provider Configuration (Vault Transit Engine)
    # -------------------------------------------------------------------------
    # The OpenBao key provider integrates with Vault's Transit Secrets Engine
    # to perform encryption and decryption operations. Keys are managed by
    # Vault and never exposed to OpenTofu.

    key_provider "openbao" "vault_transit" {
      # Vault server address
      address = var.vault_address

      # Transit secrets engine mount path (default: "transit")
      transit_engine_path = var.transit_engine_path

      # Name of the encryption key in Vault
      key_name = var.transit_key_name

      # Key length in bytes (32 bytes = 256-bit AES encryption)
      key_length = var.transit_key_length
    }

    # -------------------------------------------------------------------------
    # AES-GCM Encryption Method Configuration
    # -------------------------------------------------------------------------
    # AES-GCM (Advanced Encryption Standard - Galois/Counter Mode) provides
    # both confidentiality and authenticity.

    method "aes_gcm" "vault_method" {
      # Use the key from Vault Transit engine
      keys = key_provider.openbao.vault_transit
    }

    # -------------------------------------------------------------------------
    # State Encryption Configuration
    # -------------------------------------------------------------------------
    # Apply encryption to the OpenTofu state file to protect sensitive data.

    state {
      # Encryption method to use for state file
      method = method.aes_gcm.vault_method

      # Enforce encryption (true = fail if encryption cannot be applied)
      enforced = true
    }
  }
}
