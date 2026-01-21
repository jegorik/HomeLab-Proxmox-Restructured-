# Sentinel Journal

## 2026-01-18 - Secrets in Process List
**Vulnerability:** Passwords were passed as command-line arguments to `vault login` in shell scripts (`vault login ... password="${PASSWORD}"`).
**Learning:** Shell commands with arguments are visible in process listings (e.g., `ps aux`), exposing sensitive secrets to any user on the system.
**Prevention:** Always pass secrets via standard input (stdin) using pipes or input redirection, or use environment variables if the tool supports them safely. For `vault login`, use `password=-` and pipe the password.

## 2026-02-12 - Inconsistent Security Fix Propagation
**Vulnerability:** A known security fix (secrets in process list) was applied to some scripts (`lxc_netbox`, `netbox_settings_template`) but missed in others (`lxc_base_template`, `lxc_npm`).
**Learning:** Copy-paste code reuse across independent project directories leads to "partial patching" where vulnerabilities persist in older/forgotten copies.
**Prevention:** When fixing a pattern-based vulnerability, use `grep` or similar tools to scan the *entire* repository for other occurrences of the same pattern, not just the file currently being worked on.
