DF_PATH="./php.sqlite.Dockerfile"; [[ "$DB_MODE" = "mysql" ]] && DF_PATH="./php.mysql.Dockerfile"

# Seleção do Dockerfile com base no PHP_PROFILE
# (variáveis: PHP_PROFILE, DB_MODE, PHP_SQLITE_DF, PHP_MYSQL_DF)

pick_tpl () {
  local base="$1"  # caminho base sem sufixo (ex.: php.mysql.Dockerfile)
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


b "==> Gerando docker-compose.yml"
cat > "${COMPOSE}" <<YAML
services:
  php:
    build:
      context: .
      dockerfile: ${DF_PATH}
    container_name: ${CLIENT}_${PROJECT}_php
    working_dir: /var/www/html
    user: "0:0"
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
    container_name: ${CLIENT}_${PROJECT}_nginx
    depends_on:
      - php
    volumes:
      - ./src:/var/www/html:ro
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - app
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${CLIENT}-${PROJECT}.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.${CLIENT}-${PROJECT}.entrypoints=websecure"
      - "traefik.http.routers.${CLIENT}-${PROJECT}.tls.certresolver=le"
      - "traefik.http.routers.${CLIENT}-${PROJECT}.middlewares=${APP_CANONICAL_MW}"
      - "traefik.http.services.${CLIENT}-${PROJECT}.loadbalancer.server.port=80"
      - "traefik.docker.network=proxy"

networks:
  app:
    name: ${CLIENT}_${PROJECT}_app
  proxy:
    external: true
  db:
    external: true
YAML

save_state
