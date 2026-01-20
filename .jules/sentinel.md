# Sentinel Journal

## 2026-01-18 - Secrets in Process List
**Vulnerability:** Passwords were passed as command-line arguments to `vault login` in shell scripts (`vault login ... password="${PASSWORD}"`).
**Learning:** Shell commands with arguments are visible in process listings (e.g., `ps aux`), exposing sensitive secrets to any user on the system.
**Prevention:** Always pass secrets via standard input (stdin) using pipes or input redirection, or use environment variables if the tool supports them safely. For `vault login`, use `password=-` and pipe the password.
