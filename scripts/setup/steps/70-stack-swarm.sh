# shellcheck shell=bash
# Step 70 — gera /opt/traefik/stack.yml (Swarm)

# ===== Logging isolado do step =====
STEP_NO="70"
STEP_NAME="stack-swarm"
STEP_LOG_DIR="/var/log/setup-forcoder-logs/setup"
mkdir -p "$STEP_LOG_DIR" 2>/dev/null || true
STEP_LOG_FILE="${STEP_LOG_DIR}/step${STEP_NO}-${STEP_NAME}_$(date +%F_%H%M%S).log"

# salva FDs e duplica saída apenas dentro deste step
exec 3>&1 4>&2
exec > >(stdbuf -oL -eL tee -a "$STEP_LOG_FILE") 2>&1
echo "---- BEGIN STEP ${STEP_NO} (${STEP_NAME}) $(date -Iseconds) on $(hostname) ----"
echo "Log file: $STEP_LOG_FILE"

b "==> Gerando stack.yml (Swarm) em /opt/traefik"

STACK_DIR="/opt/traefik"
mkdir -p "${STACK_DIR}"

# Cabeçalho + networks + service traefik com UM ÚNICO 'environment:'
cat > "${STACK_DIR}/stack.yml" <<'HDR'
version: "3.9"

networks:
  proxy:
    external: true
  db:
    external: true

services:
  traefik:
    image: traefik:v2.11
    # Em Swarm, usamos deploy/labels e publish de portas TCP/UDP
    ports:
      - target: 80
        published: 80
        protocol: tcp
        mode: ingress
      - target: 443
        published: 443
        protocol: tcp
        mode: ingress
      - target: 443
        published: 443
        protocol: udp   # HTTP/3 (QUIC)
        mode: ingress

    # IMPORTANTE: único bloco 'environment'
    environment:
      - TZ=${TZ}
      - TRAEFIK_PILOT_DASHBOARD=false
      - TRAEFIK_EXPERIMENTAL_PLUGINS=false
      - TRAEFIK_GLOBAL_CHECKNEWVERSION=false
HDR

# Se ACME dns01 + Cloudflare, adiciona só a linha, SEM abrir novo 'environment:'
if [[ "$ACME_MODE" = "dns01" && -n "${CF_DNS_API_TOKEN:-}" ]]; then
  cat >> "${STACK_DIR}/stack.yml" <<'CFENV'
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
CFENV
fi

# comandos e volumes (binds em /opt/traefik no nó manager)
cat >> "${STACK_DIR}/stack.yml" <<'TAIL'
    command:
      - --log.level=INFO
      - --api.dashboard=true
      - --api.insecure=false

      - --providers.docker=true
      - --providers.docker.swarmMode=true
      - --providers.docker.exposedbydefault=false
      - --providers.docker.network=proxy
      - --providers.file.directory=/dynamic
      - --providers.file.watch=true

      # Entrypoints + redirect nativo p/ HTTPS + HTTP/3
      - --entrypoints.web.address=:80
      - --entrypoints.web.http.redirections.entryPoint.to=websecure
      - --entrypoints.web.http.redirections.entryPoint.scheme=https
      - --entrypoints.websecure.address=:443
      - --entrypoints.websecure.http3=true

      # ACME/LE
      - --certificatesresolvers.le.acme.email=${LETSENCRYPT_EMAIL}
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
TAIL

# Alterna challenge conforme modo
if [[ "$ACME_MODE" = "dns01" ]]; then
  cat >> "${STACK_DIR}/stack.yml" <<'DNS'
      - --certificatesresolvers.le.acme.dnschallenge=true
      - --certificatesresolvers.le.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.le.acme.dnschallenge.delaybeforecheck=0
DNS
else
  cat >> "${STACK_DIR}/stack.yml" <<'HTTP'
      - --certificatesresolvers.le.acme.httpchallenge=true
      - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web
HTTP
fi

cat >> "${STACK_DIR}/stack.yml" <<'REST'
      # AccessLog (JSON + filtros)
      - --accesslog=true
      - --accesslog.format=json
      - --accesslog.filepath=/logs/access.json
      - --accesslog.bufferingsize=500
      - --accesslog.fields.defaultmode=keep
      - --accesslog.fields.headers.defaultmode=drop
      - --accesslog.fields.headers.names.User-Agent=keep
      - --accesslog.fields.headers.names.Referer=keep
      - --accesslog.filters.statuscodes=400-499,500-599
      - --accesslog.filters.retryattempts=true
      - --accesslog.filters.minduration=10ms

      # Timeouts mais estáveis
      - --serversTransport.forwardingTimeouts.dialTimeout=30s
      - --serversTransport.forwardingTimeouts.responseHeaderTimeout=30s
      - --serversTransport.forwardingTimeouts.idleConnTimeout=90s
      - --serversTransport.maxIdleConnsPerHost=200

      - --global.checkNewVersion=false

    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/traefik/letsencrypt:/letsencrypt
      - /opt/traefik/dynamic:/dynamic
      - /opt/traefik/logs:/logs

    networks: ["proxy"]

    deploy:
      placement:
        constraints:
          - node.role == manager
      replicas: 1
      labels:
        - "traefik.enable=true"

        # dashboard protegido + canonical de middlewares@file
        - "traefik.http.routers.traefik.rule=Host(`${TRAEFIK_DASHBOARD_DOMAIN}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))"
        - "traefik.http.routers.traefik.entrypoints=websecure"
        - "traefik.http.routers.traefik.tls.certresolver=le"
        - "traefik.http.routers.traefik.service=api@internal"
        - "traefik.http.routers.traefik.middlewares=dashboard-auth,canonical@file"
        - "traefik.http.middlewares.dashboard-auth.basicauth.usersfile=/dynamic/auth.htpasswd"
        # evita "port is missing" para o container do traefik
        - "traefik.http.services.traefik.loadbalancer.server.port=8080"
REST

# MySQL + phpMyAdmin opcionais dentro da mesma stack (amarrados às redes)
if [[ "${USE_DB_STACK^^}" == "Y" ]]; then
cat >> "${STACK_DIR}/stack.yml" <<'DB'
  mysql:
    image: mariadb:11
    command: ["--character-set-server=utf8mb4","--collation-server=utf8mb4_unicode_ci","--max-connections=300"]
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_INITDB_SKIP_TZINFO=1
    volumes:
      - /opt/traefik/mysql-data:/var/lib/mysql
    networks: ["db"]
    deploy:
      placement:
        constraints:
          - node.role == manager

  phpmyadmin:
    image: phpmyadmin:5-apache
    environment:
      - PMA_HOST=mysql
      - PMA_ARBITRARY=0
      - UPLOAD_LIMIT=256M
      - PMA_ABSOLUTE_URI=https://${TRAEFIK_DASHBOARD_DOMAIN}/phpmyadmin/
    networks: ["proxy","db"]
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.pma.rule=Host(`${TRAEFIK_DASHBOARD_DOMAIN}`) && (PathPrefix(`/phpmyadmin`) || PathPrefix(`/phpmyadmin/`))"
        - "traefik.http.routers.pma.entrypoints=websecure"
        - "traefik.http.routers.pma.tls.certresolver=le"
        - "traefik.http.routers.pma.priority=1000"
        - "traefik.http.routers.pma.middlewares=canonical@file,pma-slash,pma-strip,pma-pfx,pma-https"
        - "traefik.http.services.pma.loadbalancer.server.port=80"
        - "traefik.http.middlewares.pma-slash.redirectregex.regex=^https?://([^/]+)/phpmyadmin$$"
        - "traefik.http.middlewares.pma-slash.redirectregex.replacement=https://$$1/phpmyadmin/"
        - "traefik.http.middlewares.pma-slash.redirectregex.permanent=true"
        - "traefik.http.middlewares.pma-strip.stripprefix.prefixes=/phpmyadmin"
        - "traefik.http.middlewares.pma-pfx.headers.customrequestheaders.X-Forwarded-Prefix=/phpmyadmin"
        - "traefik.http.middlewares.pma-https.headers.customrequestheaders.X-Forwarded-Proto=https"
        - "traefik.http.middlewares.pma-https.headers.customrequestheaders.X-Forwarded-Host=${TRAEFIK_DASHBOARD_DOMAIN}"
DB
fi

ok "stack.yml gerado em ${STACK_DIR}/stack.yml"
echo "Pré-visualização (primeiras linhas):"
nl -ba "${STACK_DIR}/stack.yml" | sed -n '1,160p' || true

echo "---- END STEP ${STEP_NO} (${STEP_NAME}) $(date -Iseconds) ----"
# restaura FDs originais
exec 1>&3 2>&4
exec 3>&- 4>&-
