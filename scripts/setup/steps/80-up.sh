# shellcheck shell=bash
b "==> Subindo stack"
cd /opt/traefik
docker compose up -d
ok "Stack ativa."
