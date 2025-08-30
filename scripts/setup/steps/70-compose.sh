# shellcheck shell=bash
b "==> Gerando docker-compose.yml"

# parte inicial + env
cat >/opt/traefik/docker-compose.yml <<'YAML'
networks:
  proxy:
    external: true
  db:
    external: true

services:
  traefik:
    image: traefik:v2.11
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443/tcp"   # HTTPS
      - "443:443/udp"   # HTTP/3 (QUIC)
    environment:
      - TZ=${TZ}
      - TRAEFIK_PILOT_DASHBOARD=false
      - TRAEFIK_EXPERIMENTAL_PLUGINS=false
      - TRAEFIK_GLOBAL_CHECKNEWVERSION=false
      - TRAEFIK_API_DISABLEDASHBOARDAD=true
YAML

# injeta CF env se dns01
if [[ "$ACME_MODE" = "dns01" && -n "$CF_DNS_API_TOKEN" ]]; then
  cat >>/opt/traefik/docker-compose.yml <<'YAML'
      - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
YAML
fi

# comandos traefik comuns (tunado)
cat >>/opt/traefik/docker-compose.yml <<'YAML'
    command:
      - --log.level=INFO
      - --api.dashboard=true
      - --api.disabledashboardad=true
      - --api.insecure=false
      - --providers.docker=true
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

      # Pilot/Plugins desligados
      - --pilot.dashboard=false

      # AccessLog (JSON em arquivo + filtros úteis)
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

      # Timeouts/Conexões mais estáveis
      - --serversTransport.forwardingTimeouts.dialTimeout=30s
      - --serversTransport.forwardingTimeouts.responseHeaderTimeout=30s
      - --serversTransport.forwardingTimeouts.idleConnTimeout=90s
      - --serversTransport.maxIdleConnsPerHost=200

      # Evitar banner/checagem de versão
      - --global.checkNewVersion=false
YAML

# ACME challenge específico
if [[ "$ACME_MODE" = "dns01" ]]; then
  cat >>/opt/traefik/docker-compose.yml <<'YAML'
      - --certificatesresolvers.le.acme.dnschallenge=true
      - --certificatesresolvers.le.acme.dnschallenge.provider=cloudflare
      - --certificatesresolvers.le.acme.dnschallenge.delaybeforecheck=0
YAML
else
  cat >>/opt/traefik/docker-compose.yml <<'YAML'
      - --certificatesresolvers.le.acme.httpchallenge=true
      - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web
YAML
fi

# volumes, network, labels, pma opcional
cat >>/opt/traefik/docker-compose.yml <<'YAML'
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
      - ./dynamic:/dynamic
      - ./logs:/logs
    networks:
      - proxy
    labels:
      - "traefik.enable=true"

      # OBS: Redirecionamento HTTP->HTTPS agora é no entrypoint (acima).
      # Mantemos as duas middlewares de canonical aqui porque o chain no arquivo dinâmico
      # injeta APENAS a que ${RESOLVED_CANONICAL} apontar (www->root OU root->www),
      # além de compress + secure-headers.

      - "traefik.http.middlewares.www-to-root.redirectregex.regex=^https?://www\\.(.*)"
      - "traefik.http.middlewares.www-to-root.redirectregex.replacement=https://$1"
      - "traefik.http.middlewares.www-to-root.redirectregex.permanent=true"

      - "traefik.http.middlewares.root-to-www.redirectregex.regex=^https?://(.*)"
      - "traefik.http.middlewares.root-to-www.redirectregex.replacement=https://www.$1"
      - "traefik.http.middlewares.root-to-www.redirectregex.permanent=true"

      - "traefik.http.routers.traefik.rule=Host(`${TRAEFIK_DASHBOARD_DOMAIN}`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=le"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.middlewares=dashboard-auth,canonical@file"
      - "traefik.http.middlewares.dashboard-auth.basicauth.usersfile=/dynamic/auth.htpasswd"
YAML

if [[ "${USE_DB_STACK^^}" == "Y" ]]; then
  cat >>/opt/traefik/docker-compose.yml <<'YAML'

  mysql:
    image: mariadb:11
    container_name: mysql
    restart: unless-stopped
    command: ["--character-set-server=utf8mb4","--collation-server=utf8mb4_unicode_ci","--max-connections=300"]
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_INITDB_SKIP_TZINFO=1
    volumes:
      - ./mysql-data:/var/lib/mysql
    networks:
      - db

  phpmyadmin:
    image: phpmyadmin:5-apache
    container_name: phpmyadmin
    restart: unless-stopped
    environment:
      - PMA_HOST=mysql
      - PMA_ARBITRARY=0
      - UPLOAD_LIMIT=256M
      - PMA_ABSOLUTE_URI=https://${TRAEFIK_DASHBOARD_DOMAIN}/phpmyadmin/
    depends_on:
      - mysql
    networks:
      - proxy
      - db
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=proxy"
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
YAML
fi
