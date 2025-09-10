# shellcheck shell=bash
b "==> Gerando stack.yml (Swarm) em /opt/traefik"

STACK_DIR="/opt/traefik"
mkdir -p "${STACK_DIR}"

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
    environment:
      - TZ=${TZ}
      - TRAEFIK_PILOT_DASHBOARD=false
      - TRAEFIK_EXPERIMENTAL_PLUGINS=false
      - TRAEFIK_GLOBAL_CHECKNEWVERSION=false
      - TRAEFIK_API_DISABLEDASHBOARDAD=true
HDR

# injeta Cloudflare env se dns01
if [[ "$ACME_MODE" = "dns01" && -n "$CF_DNS_API_TOKEN" ]]; then
  cat >> "${STACK_DIR}/stack.yml" <<'CFENV'
    environment:
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
CFENV
fi

# comandos e volumes (binds em /opt/traefik no nó manager)
cat >> "${STACK_DIR}/stack.yml" <<'TAIL'
    command:
      - --log.level=INFO
      - --api.dashboard=true
      - --api.disabledashboardad=true
      - --api.insecure=false

      - --providers.swarm=true
      - --providers.docker.swarmMode=true
      - --providers.docker.exposedbydefault=false
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

        # middlewares canonical (www <-> root) ficam definidos em file provider (dynamic/)
        - "traefik.http.routers.traefik.rule=Host(`${TRAEFIK_DASHBOARD_DOMAIN}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))"
        - "traefik.http.routers.traefik.entrypoints=websecure"
        - "traefik.http.routers.traefik.tls.certresolver=le"
        - "traefik.http.routers.traefik.service=api@internal"
        - "traefik.http.routers.traefik.middlewares=dashboard-auth,canonical@file"
        - "traefik.http.middlewares.dashboard-auth.basicauth.usersfile=/dynamic/auth.htpasswd"
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
        - "traefik.http.middlewares.pma-slash.redirectregex.regex=^https?://([^/]+)/phpmyadmin$"
        - "traefik.http.middlewares.pma-slash.redirectregex.replacement=https://$1/phpmyadmin/"
        - "traefik.http.middlewares.pma-slash.redirectregex.permanent=true"
        - "traefik.http.middlewares.pma-strip.stripprefix.prefixes=/phpmyadmin"
        - "traefik.http.middlewares.pma-pfx.headers.customrequestheaders.X-Forwarded-Prefix=/phpmyadmin"
        - "traefik.http.middlewares.pma-https.headers.customrequestheaders.X-Forwarded-Proto=https"
        - "traefik.http.middlewares.pma-https.headers.customrequestheaders.X-Forwarded-Host=${TRAEFIK_DASHBOARD_DOMAIN}"
DB
fi
