#!/usr/bin/env bash
set -euo pipefail

# =============== delclient.sh =====================
# Derruba a stack de um projeto, remove /home/<cliente>/<projeto>
# e (opcional) DROP DATABASE + DROP USER no MySQL central.
# Preserva o usuário <cliente>.
# Segurança: NUNCA "adivinha" DB/USER. Só dropa se vier de fonte confiável (.env ou metadata).
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

guard_username(){
  local u="$1"
  [[ "$u" =~ ^[a-z0-9_]{1,32}$ ]] || die "Nome de usuário suspeito/inválido: '$u'"
}

# Lê KEY=VALUE de um arquivo estilo .env (última ocorrência não comentada)
get_env_kv(){
  # uso: get_env_kv ARQUIVO CHAVE
  local file="$1" key="$2" raw
  [ -f "$file" ] || return 1
  raw="$(grep -E "^[[:space:]]*${key}=" "$file" | grep -v '^[[:space:]]*#' | tail -n1 | cut -d= -f2- | sed 's/[[:space:]]*$//')"
  [ -n "${raw:-}" ] || return 1
  # remove aspas de borda se existirem
  raw="${raw%\"}"; raw="${raw#\"}"
  raw="${raw%\'}"; raw="${raw#\'}"
  printf '%s' "$raw"
}

mysql_exec(){
  docker exec -i mysql mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" "$@"
}

mysql_scalar(){
  local q="$1"
  mysql_exec -N -e "$q" 2>/dev/null | tr -d '\r'
}

need_root

read -rp "Cliente (ex.: cliente1): " CLIENT
read -rp "Projeto (ex.: site): " PROJECT
[ -n "$CLIENT" ] && [ -n "$PROJECT" ] || die "Cliente/Projeto obrigatórios."

ROOT="/home/${CLIENT}/${PROJECT}"
SRC_DIR="${ROOT}/src"
COMPOSE="${ROOT}/docker-compose.yml"

[ -d "$ROOT" ] || die "Projeto não encontrado: $ROOT"

# ---- Descoberta segura de DB_NAME/DB_USER ----
ENV_PATH="${SRC_DIR}/.env"
META_PATH="${ROOT}/.provision/db.info"   # opcional: mkclient pode gravar isso
DB_FROM="none"
DB_NAME=""
DB_USER=""

if [ -f "$ENV_PATH" ]; then
  DB_CONNECTION="$(get_env_kv "$ENV_PATH" "DB_CONNECTION" || true)"
  DB_DATABASE="$(get_env_kv "$ENV_PATH" "DB_DATABASE"  || true)"
  DB_USERNAME="$(get_env_kv "$ENV_PATH" "DB_USERNAME"  || true)"
  if [ "${DB_CONNECTION:-}" = "mysql" ] && [ -n "${DB_DATABASE:-}" ]; then
    DB_NAME="$DB_DATABASE"
    DB_USER="${DB_USERNAME:-}"
    DB_FROM="env"
  fi
fi

if [ "$DB_FROM" = "none" ] && [ -f "$META_PATH" ]; then
  DB_NAME="$(get_env_kv "$META_PATH" "DB_NAME" || true)"
  DB_USER="$(get_env_kv "$META_PATH" "DB_USER" || true)"
  if [ -n "$DB_NAME" ]; then
    DB_FROM="meta"
  fi
fi

# ---- Resumo ----
b "Resumo da remoção"
echo " - Cliente : $CLIENT"
echo " - Projeto : $PROJECT"
echo " - Path    : $ROOT"
echo " - Compose : $([ -f "$COMPOSE" ] && echo 'encontrado' || echo 'N/A')"
if [ "$DB_FROM" != "none" ]; then
  echo " - DB alvo : ${DB_NAME} (user: ${DB_USER:-(não definido)})  [fonte: $DB_FROM]"
else
  echo " - DB alvo : (indefinido — DROP desabilitado por segurança)"
fi
echo
read -rp "CONFIRME digitando 'DELETE' para prosseguir com a remoção de arquivos/containers: " CONFIRM
[ "$CONFIRM" = "DELETE" ] || die "Cancelado."

# ---- Compose down / parar restos ----
if [ -f "$COMPOSE" ]; then
  b "Derrubando containers com docker compose..."
  ( cd "$ROOT" && docker compose down --remove-orphans ) || warn "Falha ao derrubar via compose (pode já estar parado)."
else
  warn "docker-compose.yml não encontrado — pulando 'compose down'."
  for S in php nginx; do
    CNAME="${CLIENT}_${PROJECT}_${S}"
    if docker ps -a --format '{{.Names}}' | grep -qx "$CNAME"; then
      warn "Removendo container solto: $CNAME"
      docker rm -f "$CNAME" || true
    fi
  done
fi

# ---- Perguntar sobre DROP no MySQL central (somente se DB_FROM != none) ----
DROP_MYSQL=0
DB_EXISTS=0
USER_EXISTS=0

if [ "$DB_FROM" != "none" ]; then
  if docker ps --format '{{.Names}}' | grep -qx mysql && [ -f /opt/traefik/.env ]; then
    # shellcheck disable=SC1091
    . /opt/traefik/.env || true
    if [ -z "${MYSQL_ROOT_PASSWORD:-}" ]; then
      warn "MYSQL_ROOT_PASSWORD não encontrado em /opt/traefik/.env — sem DROP automático."
    else
      guard_dbname "$DB_NAME"
      [ -n "${DB_USER:-}" ] && guard_username "$DB_USER" || true

      EXIST_DB="$(mysql_scalar "SHOW DATABASES LIKE '${DB_NAME//\'/\\\'}';" || true)"
      if [ "$EXIST_DB" = "$DB_NAME" ]; then DB_EXISTS=1; fi

      if [ -n "${DB_USER:-}" ]; then
        CNT_USER="$(mysql_scalar "SELECT COUNT(*) FROM mysql.user WHERE user='${DB_USER//\'/\\\'}';" || echo "0")"
        if [ "${CNT_USER:-0}" -gt 0 ]; then USER_EXISTS=1; fi
      fi

      echo
      if [ "$DB_EXISTS" -eq 1 ] || [ "$USER_EXISTS" -eq 1 ]; then
        echo "Detectado no MySQL central:"
        [ "$DB_EXISTS" -eq 1 ] && echo "  - DB existe : ${DB_NAME}" || echo "  - DB existe : não"
        if [ -n "${DB_USER:-}" ]; then
          [ "$USER_EXISTS" -eq 1 ] && echo "  - USER existe: ${DB_USER}" || echo "  - USER existe: não"
        else
          echo "  - USER       : (não informado)"
        fi

        read -rp "Deseja dropar o que existe (DB e/ou USER)? [y/N]: " ANS
        if [[ "${ANS:-N}" =~ ^[Yy]$ ]]; then
          echo
          echo "Confirmação forte: digite exatamente:  DROP ${DB_NAME}"
          read -rp "> " CONFSTR
          [ "$CONFSTR" = "DROP ${DB_NAME}" ] || die "Confirmação não confere. Abortado o DROP."
          DROP_MYSQL=1
        fi
      else
        warn "Nem DB nem USER encontrados — não há o que dropar."
      fi
    fi
  else
    warn "Container 'mysql' inativo ou /opt/traefik/.env ausente — pulando checagem/DROP do DB."
  fi
else
  warn "Sem .env (mysql) e sem metadata — DROP de DB desabilitado por segurança."
fi

if [ "$DROP_MYSQL" -eq 1 ]; then
  b "Executando DROP no MySQL central..."
  if [ "$DB_EXISTS" -eq 1 ]; then
    mysql_exec -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" || die "Falha ao dropar DB."
    ok "DB \`${DB_NAME}\` removido."
  else
    warn "DB \`${DB_NAME}\` não existe — skip."
  fi

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

# ---- Remove pasta do projeto ----
if [[ "$ROOT" == /home/*/* && "$ROOT" != "/home/" && -n "$CLIENT" && -n "$PROJECT" ]]; then
  b "Removendo pasta do projeto..."
  rm -rf --one-file-system --preserve-root "$ROOT"
  ok "Pasta removida: $ROOT"
else
  die "Guardrail acionado: caminho inválido para rm -rf ($ROOT)."
fi

b "Concluído."
echo "O usuário Linux '${CLIENT}' foi preservado."
