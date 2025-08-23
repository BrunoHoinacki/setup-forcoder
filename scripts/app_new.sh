#!/usr/bin/env bash
# Cria e deploya um app Laravel no Swarm via Traefik
set -Eeuo pipefail
cd "$(dirname "$0")/.." # vai para raiz do repo

source .env
source scripts/lib.sh

EDGE="${EDGE:-edge}"
WORKSPACE="${WORKSPACE:-/workspace}"

echo "==> Novo app Laravel (Swarm + Traefik)"

APP_NAME=$(prompt "APP_NAME" "Nome do app (stack) ex: app1")
APP_DOMAIN=$(prompt "APP_DOMAIN" "Domínio (ou subdomínio) ex: app1.seudominio.com")
GIT_URL=$(prompt "GIT_URL" "URL do repositório Git (vazio para pular)" "")
DB_PASSWORD=$(prompt "DB_PASSWORD" "Senha do MySQL (gerar aleatória se vazio)" "")

if [[ -z "${APP_NAME}" || -z "${APP_DOMAIN}" ]]; then
  echo "ERRO: APP_NAME e APP_DOMAIN são obrigatórios."
  exit 1
fi

if [[ -z "$DB_PASSWORD" ]]; then
  DB_PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16 || true)"
fi

APP_DIR="${WORKSPACE}/${APP_NAME}"
mkdir -p "$APP_DIR"

# Opcional: clonar código
if [[ -n "$GIT_URL" ]]; then
  if [[ -d "${APP_DIR}/.git" ]]; then
    echo ">> Diretório já é um repo Git. Pulando clone."
  else
    echo ">> Clonando ${GIT_URL} em ${APP_DIR}…"
    git clone --depth=1 "$GIT_URL" "$APP_DIR"
  fi
else
  # cria um placeholder se não houver código
  if [[ ! -d "${APP_DIR}/public" ]]; then
    mkdir -p "${APP_DIR}/public"
    echo "<?php echo 'Laravel placeholder - configure seu projeto em ${APP_DIR}';" > "${APP_DIR}/public/index.php"
  fi
fi

# Gerar docker-compose a partir do template
TMP_FILE="/tmp/${APP_NAME}_compose.yml"
export APP_NAME APP_DOMAIN APP_DIR DB_PASSWORD EDGE

envsubst < templates/laravel/docker-compose.yml.tpl > "$TMP_FILE"

# Nginx conf
NGINX_DIR="${APP_DIR}/.deploy/nginx"
mkdir -p "$NGINX_DIR"
export APP_SERVER_NAME="$APP_DOMAIN"
envsubst < templates/laravel/nginx.conf.tpl > "${NGINX_DIR}/default.conf"

echo ">> Fazendo deploy: stack ${APP_NAME}"
docker stack deploy -c "$TMP_FILE" "$APP_NAME"

echo
echo "OK: App deployado!"
echo " - Stack: ${APP_NAME}"
echo " - Domínio: https://${APP_DOMAIN}"
echo " - Código: ${APP_DIR}"
echo " - MySQL senha: ${DB_PASSWORD}"
