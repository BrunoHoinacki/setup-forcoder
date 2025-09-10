# shellcheck shell=bash
# Step 60 — prepara estrutura do Traefik e arquivos dinâmicos + .env

# ===== Logging isolado do step =====
STEP_NO="60"
STEP_NAME="traefik-files"
STEP_LOG_DIR="/var/log/setup-forcoder-logs/setup"
mkdir -p "$STEP_LOG_DIR" 2>/dev/null || true
STEP_LOG_FILE="${STEP_LOG_DIR}/step${STEP_NO}-${STEP_NAME}_$(date +%F_%H%M%S).log"

# salva FDs e duplica saída apenas dentro deste step
exec 3>&1 4>&2
exec > >(stdbuf -oL -eL tee -a "$STEP_LOG_FILE") 2>&1
echo "---- BEGIN STEP ${STEP_NO} (${STEP_NAME}) $(date -Iseconds) on $(hostname) ----"
echo "Log file: $STEP_LOG_FILE"

b "==> Preparando /opt/traefik e /opt/zips/"
mkdir -p /opt/traefik/letsencrypt /opt/traefik/dynamic /opt/traefik/mysql-data
mkdir -p /opt/traefik/logs
mkdir -p /opt/zips/
rm -f /opt/traefik/letsencrypt/acme.json
touch /opt/traefik/letsencrypt/acme.json
chmod 600 /opt/traefik/letsencrypt/acme.json

# .env opcional (documenta variáveis) — o deploy usa as variáveis exportadas pelo shell
cat >/opt/traefik/.env <<EOF
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
TRAEFIK_DASHBOARD_DOMAIN=${TRAEFIK_DASHBOARD_DOMAIN}
TZ=${TZ}
CANONICAL_MW=${CANONICAL_MW}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
HTPASSWD_ESCAPED=${HTPASSWD_ESCAPED}
CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
EOF
ok ".env escrito em /opt/traefik/.env"

# Middlewares dinâmicos (compress + security headers + canonical)
# Define www-to-root / root-to-www preservando o PATH
cat >/opt/traefik/dynamic/middlewares.yml <<EOF
http:
  middlewares:
    www-to-root:
      redirectRegex:
        regex: "^https?://www\\.(.+?)(/.*)?$"
        replacement: "https://\\1\\2"
        permanent: true

    root-to-www:
      redirectRegex:
        regex: "^https?://([^/]+)(/.*)?$"
        replacement: "https://www.\\1\\2"
        permanent: true

    canonical:
      chain:
        middlewares:
          - ${CANONICAL_MW}
          - compress
          - secure-headers

    compress:
      compress: {}

    secure-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        browserXssFilter: true
        contentTypeNosniff: true
        frameDeny: true
        referrerPolicy: no-referrer-when-downgrade
        customRequestHeaders:
          X-Forwarded-Proto: https
EOF
ok "dynamic/middlewares.yml gerado"

# Auth do dashboard (se existir)
if [ -n "${HTPASSWD_ESCAPED:-}" ]; then
  printf '%s\n' "${HTPASSWD_ESCAPED//\$\$/\$}" > /opt/traefik/dynamic/auth.htpasswd
  chmod 640 /opt/traefik/dynamic/auth.htpasswd
  ok "dynamic/auth.htpasswd gerado"
else
  warn "HTPASSWD_ESCAPED vazio; dashboard ficará sem usersfile até gerar um hash."
fi

echo "---- END STEP ${STEP_NO} (${STEP_NAME}) $(date -Iseconds) ----"
# restaura FDs originais
exec 1>&3 2>&4
exec 3>&- 4>&-
