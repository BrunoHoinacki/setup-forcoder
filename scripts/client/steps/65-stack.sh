#!/usr/bin/env bash
set -euo pipefail

if [[ "${MODE}" != "swarm" ]]; then
  ok "MODE=${MODE} → pulando step de stack Swarm."
  exit 0
fi

# Seleciona Dockerfile efetivo
DF_PATH="./php.sqlite.Dockerfile"; [[ "$DB_MODE" = "mysql" ]] && DF_PATH="./php.mysql.Dockerfile"

pick_tpl () {
  local base="$1"
  local profile="${PHP_PROFILE:-min}"
  case "$profile" in
    full) cp -f "${base}.full.tpl" "${base}";;
    min|*) cp -f "${base}.min.tpl"  "${base}";;
  esac
}
if [[ "${DB_MODE}" = "mysql" ]]; then
  pick_tpl "${PHP_MYSQL_DF}"
else
  pick_tpl "${PHP_SQLITE_DF}"
fi

b "==> Gerando stack.yml (Swarm)"
cat > "${STACK_FILE}" <<YAML
version: "3.9"

networks:
  proxy:
    external: true
  db:
    external: true
  app:
    driver: overlay

services:
  php:
    image: ${CLIENT}_${PROJECT}_php:latest
    build:
      context: .
      dockerfile: ${DF_PATH}
    deploy:
      mode: replicated
      replicas: 1
      restart_policy: { condition: on-failure }
    working_dir: /var/www/html
    environment:
      COMPOSER_CACHE_DIR: /tmp/composer-cache
      COMPOSER_MEMORY_LIMIT: -1
    volumes:
      - ./src:/var/www/html
      - ./.composer-cache:/tmp/composer-cache
    networks:
      - app
$( [[ "$DB_MODE" = "mysql" ]] && echo "      - db" )

  nginx:
    image: nginx:1.27-alpine
    deploy:
      mode: replicated
      replicas: 1
      restart_policy: { condition: on-failure }
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=proxy"
        - "traefik.http.routers.${CLIENT}-${PROJECT}.rule=Host(\`${DOMAIN}\`)"
        - "traefik.http.routers.${CLIENT}-${PROJECT}.entrypoints=websecure"
        - "traefik.http.routers.${CLIENT}-${PROJECT}.tls.certresolver=le"
        - "traefik.http.routers.${CLIENT}-${PROJECT}.middlewares=${APP_CANONICAL_MW}"
        - "traefik.http.services.${CLIENT}-${PROJECT}.loadbalancer.server.port=80"
    depends_on:
      - php
    volumes:
      - ./src:/var/www/html:ro
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - app
      - proxy
YAML

save_state
