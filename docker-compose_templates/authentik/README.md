# Authentik is an open-source identity and access management solution

## Quick start

1. Create the `.env` file in this directory.
2. Place overrides in a local `.env` file in this directory.
3. Run the following commands to generate a password and secret key and write them to your .env file:
   - `echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env` for the database password
   - `echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env` for the secret key
4. Run `docker compose -f compose.yml up -d`.

## Notes

- The default image is `ghcr.io/goauthentik/server` and the default tag is `2025.12.1`.
- The default ports are `9000` for HTTP and `9443` for HTTPS.
- The default database name is `authentik` and the default database user is `authentik`.
