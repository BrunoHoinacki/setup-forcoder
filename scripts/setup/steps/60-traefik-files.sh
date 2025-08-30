# shellcheck shell=bash
b "==> Preparando /opt/traefik e /opt/zips/"
mkdir -p /opt/traefik/letsencrypt /opt/traefik/dynamic /opt/traefik/mysql-data
mkdir -p /opt/traefik/logs
mkdir -p /opt/zips/
rm -f /opt/traefik/letsencrypt/acme.json
touch /opt/traefik/letsencrypt/acme.json
chmod 600 /opt/traefik/letsencrypt/acme.json

cat >/opt/traefik/.env <<EOF
LETSENCRYPT_EMAIL=${LE_EMAIL}
TRAEFIK_DASHBOARD_DOMAIN=${DASH_DOMAIN}
TZ=America/Sao_Paulo
CANONICAL_MW=${CANONICAL_MW}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
HTPASSWD_ESCAPED=${HTPASSWD_ESCAPED}
CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
EOF

# Middlewares dinâmicos (compress + security headers + canonical)
cat >/opt/traefik/dynamic/middlewares.yml <<EOF
http:
  middlewares:
    canonical:
      chain:
        middlewares:
          - ${RESOLVED_CANONICAL}
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

if [ -n "${HTPASSWD_ESCAPED:-}" ]; then
  printf '%s\n' "${HTPASSWD_ESCAPED//\$\$/\$}" > /opt/traefik/dynamic/auth.htpasswd
  chmod 640 /opt/traefik/dynamic/auth.htpasswd
else
  warn "HTPASSWD_ESCAPED vazio; dashboard ficará sem usersfile até gerar um hash."
fi
