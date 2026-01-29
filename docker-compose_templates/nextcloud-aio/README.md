# Nextcloud AIO is a Docker-based solution for running Nextcloud.

## Quick start

1. Create the `.env` file in this directory.
2. Place overrides in a local `.env` file in this directory.
3. Run `docker compose -f compose.yml up -d`.

## Notes

- The default image is `nextcloud/all-in-one` and the default tag is `latest`.
- The default ports are `8080` for HTTP and `11000` for HTTPS.
- The default data directory is `/mnt/nextcloud-data`.
