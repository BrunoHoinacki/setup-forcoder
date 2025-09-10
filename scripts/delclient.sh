#!/usr/bin/env bash
set -euo pipefail

# =============== delclient.sh =====================
# Remove um projeto provisionado pelo mkclient (Compose OU Swarm):
#  - derruba Compose (docker compose down) OU stack Swarm (docker stack rm)
#  - remove /home/<cliente>/<projeto>
#  - (opcional) DROP DATABASE + DROP USER no MySQL central
# Segurança: só dropa DB/USER se vier de .env/metadata confiável
# ==================================================

b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo "  [OK] $*"; }
warn(){ echo "  [!] $*"; }
die(){ echo "  [ERR] $*" >&2; exit 1; }
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo su)."; }

guard_dbname(){
  local n="$1"
  [[ "$n" =~ ^[a-z0-9_]{1,64}$ ]] || die "Nome de DB suspeito/inválido: '$n'"
  case "$n" in
    mysql|information_schema|performance_schema|sys) die "Recusando dropar DB do sistema: $n";;
  esac
}
guard_username(){ [[ "$1" =~ ^[a-z0-9_]{1,32}$ ]] || die "Nome de usuário suspeito/inválido: '$1'"; }

# .env reader (última ocorrência, sem comentários; remove aspas de borda)
get_env_kv(){
  local file="$1" key="$2" raw
  [ -f "$file" ] || return 1
  raw="$(grep -E "^[[:space:]]*${key}=" "$file" | grep -v '^[[:space:]]*#' | tail -n1 | cut -d= -f2- | sed 's/[[:space:]]*$//')"
  [ -n "${raw:-}" ] || return 1
  raw="${raw%\"}"; raw="${raw#\"}"; raw="${raw%\'}"; raw="${raw#\'}"
  printf '%s' "$raw"
}

# Nome de stack seguro (minúsculas, a-z0-9-, comprimento razoável)
sanitize_stack(){
  local s="$1"
  s="$(echo -n "$s" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--\+/-/g' | sed 's/^-//;s/-$//')"
  printf '%s' "${s:0:48}"
}

swarm_wait_stack_gone(){
  local stack="$1" t=0 timeout=90
  while [ $t -lt $timeout ]; do
    if ! docker stack services "$stack" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2; t=$((t+2))
  done
  return 1
}

mysql_exec(){ docker exec -i mysql mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" "$@"; }
mysql_scalar(){ mysql_exec -N -e "$1" 2>/dev/null | tr -d '\r'; }

need_root

read -rp "Cliente (ex.: cliente1): " CLIENT
read -rp "Projeto (ex.: site): " PROJECT
[ -n "$CLIENT" ] && [ -n "$PROJECT" ] || die "Cliente/Projeto obrigatórios."

ROOT="/home/${CLIENT}/${PROJECT}"
SRC_DIR="${ROOT}/src"
COMPOSE="${ROOT}/docker-compose.yml"
STACK_FILE="${ROOT}/stack.yml"
STATE="${ROOT}/.provision/state.env"

[ -d "$ROOT" ] || die "Projeto não encontrado: $ROOT"

# ---- Detectar MODE/STACK_NAME ----
MODE="compose"
STACK_NAME=""
if [ -f "$STATE" ]; then
  # shellcheck disable=SC1090
  . "$STATE" || true
  # state pode ter MODE/STACK_NAME; se não tiver, inferimos
fi

if [ -z "${MODE:-}" ]; then
  if [ -f "$STACK_FILE" ]; then MODE="swarm"; else MODE="compose"; fi
fi

if [ -z "${STACK_NAME:-}" ]; then
  # heurística padrão: cliente-projeto
  STACK_NAME="$(sanitize_stack "${CLIENT}-${PROJECT}")"
fi

# ---- Descoberta segura de DB_NAME/DB_USER ----
ENV_PATH="${SRC_DIR}/.env"
META_PATH="${ROOT}/.provision/db.info"
DB_FROM="none"; DB_NAME=""; DB_USER=""

if [ -f "$ENV_PATH" ]; then
  DB_CONNECTION="$(get_env_kv "$ENV_PATH" "DB_CONNECTION" || true)"
  DB_DATABASE="$(get_env_kv "$ENV_PATH" "DB_DATABASE"  || true)"
  DB_USERNAME="$(get_env_kv "$ENV_PATH" "DB_USERNAME"  || true)"
  if [ "${DB_CONNECTION:-}" = "mysql" ] && [ -n "${DB_DATABASE:-}" ]; then
    DB_NAME="$DB_DATABASE"; DB_USER="${DB_USERNAME:-}"; DB_FROM="env"
  fi
fi
if [ "$DB_FROM" = "none" ] && [ -f "$META_PATH" ]; then
  DB_NAME="$(get_env_kv "$META_PATH" "DB_NAME" || true)"
  DB_USER="$(get_env_kv "$META_PATH" "DB_USER" || true)"
  [ -n "$DB_NAME" ] && DB_FROM="meta"
fi

# ---- Resumo ----
b "Resumo da remoção"
echo " - Cliente : $CLIENT"
echo " - Projeto : $PROJECT"
echo " - Path    : $ROOT"
echo " - Mode    : $MODE"
if [ "$MODE" = "compose" ]; then
  echo " - Compose : $([ -f "$COMPOSE" ] && echo 'encontrado' || echo 'N/A')"
else
  echo " - Stack   : ${STACK_NAME}  ($([ -f "$STACK_FILE" ] && echo 'stack.yml encontrado' || echo 'sem stack.yml'))"
fi
if [ "$DB_FROM" != "none" ]; then
  echo " - DB alvo : ${DB_NAME} (user: ${DB_USER:-(não definido)})  [fonte: $DB_FROM]"
else
  echo " - DB alvo : (indefinido — DROP desabilitado por segurança)"
fi
echo
read -rp "CONFIRME digitando 'DELETE' para prosseguir com a remoção: " CONFIRM
[ "$CONFIRM" = "DELETE" ] || die "Cancelado."

# ---- Derrubar (Compose ou Swarm) ----
if [ "$MODE" = "swarm" ]; then
  b "Derrubando stack Swarm: ${STACK_NAME}"
  set +e
  docker stack rm "$STACK_NAME"
  set -e
  if swarm_wait_stack_gone "$STACK_NAME"; then
    ok "Stack removida."
  else
    warn "Timeout aguardando remoção completa da stack (seguindo)."
  fi
else
  if [ -f "$COMPOSE" ]; then
    b "Derrubando containers (docker compose down --volumes)..."
    ( cd "$ROOT" && docker compose down --remove-orphans --volumes ) || warn "Falha ao derrubar via compose (pode já estar parado)."
  else
    warn "docker-compose.yml não encontrado — removendo containers soltos (se houver)."
    for S in php nginx; do
      CNAME="${CLIENT}_${PROJECT}_${S}"
      docker ps -a --format '{{.Names}}' | grep -qx "$CNAME" && { docker rm -f "$CNAME" || true; }
    done
  fi
fi

# ---- Perguntar sobre DROP no MySQL central (somente se DB_FROM != none) ----
DROP_MYSQL=0 DB_EXISTS=0 USER_EXISTS=0
if [ "$DB_FROM" != "none" ]; then
  if docker ps --format '{{.Names}}' | grep -qx mysql && [ -f /opt/traefik/.env ]; then
    . /opt/traefik/.env || true
    if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then
      guard_dbname "$DB_NAME"
      [ -n "${DB_USER:-}" ] && guard_username "$DB_USER" || true

      EXIST_DB="$(mysql_scalar "SHOW DATABASES LIKE '${DB_NAME//\'/\\\'}';" || true)"
      [ "$EXIST_DB" = "$DB_NAME" ] && DB_EXISTS=1
      if [ -n "${DB_USER:-}" ]; then
        CNT_USER="$(mysql_scalar "SELECT COUNT(*) FROM mysql.user WHERE user='${DB_USER//\'/\\\'}';" || echo "0")"
        [ "${CNT_USER:-0}" -gt 0 ] && USER_EXISTS=1
      fi

      if [ "$DB_EXISTS" -eq 1 ] || [ "$USER_EXISTS" -eq 1 ]; then
        echo
        echo "Detectado no MySQL central:"
        [ "$DB_EXISTS" -eq 1 ] && echo "  - DB existe : ${DB_NAME}" || echo "  - DB existe : não"
        if [ -n "${DB_USER:-}" ]; then
          [ "$USER_EXISTS" -eq 1 ] && echo "  - USER existe: ${DB_USER}" || echo "  - USER existe: não"
        else
          echo "  - USER       : (não informado)"
        fi
        read -rp "Dropar DB/USER acima? [y/N]: " ANS
        if [[ "${ANS:-N}" =~ ^[Yy]$ ]]; then
          echo "Confirmação forte: digite exatamente:  DROP ${DB_NAME}"
          read -rp "> " CONFSTR
          [ "$CONFSTR" = "DROP ${DB_NAME}" ] || die "Confirmação não confere. Abortado o DROP."
          DROP_MYSQL=1
        fi
      else
        warn "Nem DB nem USER encontrados — não há o que dropar."
      fi
    else
      warn "MYSQL_ROOT_PASSWORD ausente em /opt/traefik/.env — sem DROP automático."
    fi
  else
    warn "Container 'mysql' inativo OU /opt/traefik/.env ausente — pulando DROP do DB."
  fi
fi

if [ "$DROP_MYSQL" -eq 1 ]; then
  b "Executando DROP no MySQL central..."
  [ "$DB_EXISTS" -eq 1 ] && { mysql_exec -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" || die "Falha ao dropar DB."; ok "DB \`${DB_NAME}\` removido."; } || warn "DB \`${DB_NAME}\` não existe — skip."
  if [ -n "${DB_USER:-}" ]; then
    if [ "$USER_EXISTS" -eq 1 ]; then
      mysql_exec -e "DROP USER IF EXISTS '${DB_USER}'@'%';" || warn "Falha ao dropar USER '@%'."
      mysql_exec -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';" || true
      mysql_exec -e "FLUSH PRIVILEGES;" || true
      ok "Usuário '${DB_USER}' removido."
    else
      warn "Usuário '${DB_USER}' não existe — skip."
    fi
  fi
fi

# ---- Remover pasta do projeto ----
if [[ "$ROOT" == /home/*/* && "$ROOT" != "/home/" && -n "$CLIENT" && -n "$PROJECT" ]]; then
  b "Removendo pasta do projeto..."
  rm -rf --one-file-system --preserve-root "$ROOT"
  ok "Pasta removida: $ROOT"
else
  die "Guardrail acionado: caminho inválido para rm -rf ($ROOT)."
fi

b "Concluído."
echo "O usuário Linux '${CLIENT}' foi preservado."
