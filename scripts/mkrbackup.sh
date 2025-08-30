#!/usr/bin/env bash
set -euo pipefail

# =============== mkrbackup.sh (non-interactive) =================
# Varre /home/<cliente>/<projeto>/src e, para cada projeto:
#  - garante /opt/rbackup/<cliente>/<projeto>/{dumps,src}
#  - faz dump SQL (overwrite): dumps/dump.sql
#  - garante bind mount RO de /home/<c>/<p>/src -> /opt/rbackup/<c>/<p>/src
# Lê .env do projeto para credenciais MySQL/MariaDB.
# Requisitos: root; docker; container "mysql" OU "mariadb" em execução.
# ================================================================

b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo "  [OK] $*"; }
warn(){ echo "  [!] $*"; }
err(){ echo "  [ERR] $*" >&2; }

# raiz dos backups remotos (SINGULAR)
RBROOT="/opt/rbackup"

# modo do dump.sql (padrão: 0644 = todos leem; altere com RB_DUMP_MODE=0640 se preferir)
RB_DUMP_MODE="${RB_DUMP_MODE:-0644}"

# ----- lock para evitar concorrência -----
LOCK="/var/lock/mkrbackup.lock"
mkdir -p "$(dirname "$LOCK")"
exec 9> "$LOCK"
flock -n 9 || { warn "Outra execução em andamento. Saindo."; exit 0; }

# ----- utils -----
get_env_kv(){
  local file="$1" key="$2" raw
  [ -f "$file" ] || { echo ""; return 0; }
  raw="$(grep -E "^[[:space:]]*${key}=" "$file" | grep -v '^[[:space:]]*#' | tail -n1 | cut -d= -f2- | sed 's/[[:space:]]*$//')"
  raw="${raw%\"}"; raw="${raw#\"}"; raw="${raw%\'}"; raw="${raw#\'}"
  printf '%s' "$raw"
}

detect_db_container(){
  if docker ps --format '{{.Names}}' | grep -qx mysql; then
    echo "mysql"; return 0
  fi
  if docker ps --format '{{.Names}}' | grep -qx mariadb; then
    echo "mariadb"; return 0
  fi
  echo ""; return 1
}

dump_mysql_sql(){
  # Gera dump SQL "sem gzip" (overwrite atômico)
  local db_host="$1" db_port="$2" db_name="$3" db_user="$4" db_pass="$5" out_sql="$6"

  local ctn; ctn="$(detect_db_container || true)"
  if [ -z "$ctn" ]; then
    warn "Sem container mysql/mariadb — pulando dump de $db_name."
    return 1
  fi

  local CLIENT_BIN="mysqldump"
  if ! docker exec "$ctn" sh -lc "command -v mysqldump >/dev/null 2>&1"; then
    if docker exec "$ctn" sh -lc "command -v mariadb-dump >/dev/null 2>&1"; then
      CLIENT_BIN="mariadb-dump"
    else
      warn "mysqldump/mariadb-dump não encontrados no container '$ctn'."
      return 1
    fi
  fi

  # defaults-extra-file criado no host e copiado
  local HOST_AUTH_FILE CTN_AUTH_FILE
  HOST_AUTH_FILE="$(mktemp)"
  CTN_AUTH_FILE="/tmp/.mydump.cnf"
  chmod 600 "$HOST_AUTH_FILE"
  cat >"$HOST_AUTH_FILE" <<EOF
[client]
user=$db_user
password=$db_pass
host=$db_host
port=$db_port
EOF

  docker cp "$HOST_AUTH_FILE" "$ctn":"$CTN_AUTH_FILE" >/dev/null
  rm -f "$HOST_AUTH_FILE" || true
  docker exec "$ctn" sh -lc "chmod 600 $CTN_AUTH_FILE" >/dev/null

  local COMMON_FLAGS="--single-transaction --routines --events --triggers"
  local TMP_SQL; TMP_SQL="$(mktemp "${out_sql}.XXXXXX")"

  set +e
  docker exec "$ctn" sh -lc "$CLIENT_BIN --defaults-extra-file=$CTN_AUTH_FILE $COMMON_FLAGS $db_name" \
    > "$TMP_SQL"
  local rc=$?
  docker exec "$ctn" sh -lc "rm -f $CTN_AUTH_FILE" >/dev/null 2>&1 || true
  set -e

  if [ $rc -ne 0 ] || [ ! -s "$TMP_SQL" ]; then
    rm -f "$TMP_SQL" || true
    warn "Dump falhou para DB '$db_name' (rc=$rc)."
    return 1
  fi

  mv -f "$TMP_SQL" "$out_sql"
  chmod "$RB_DUMP_MODE" "$out_sql" || true
  ok "Dump salvo: $out_sql"
  return 0
}

# Normaliza SOURCE que o findmnt pode retornar como /dev/sdX[/path]
normalize_findmnt_source(){
  local src="$1"
  if [[ "$src" =~ \[(.*)\] ]]; then
    echo "/${BASH_REMATCH[1]}"
  else
    echo "$src"
  fi
}

ensure_bind_ro(){
  local src="$1" tgt="$2"
  [ -d "$src" ] || { warn "SRC inexistente: $src"; return 1; }
  mkdir -p "$tgt"

  if command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$tgt"; then
    local cur_src; cur_src="$(findmnt -n -o SOURCE --target "$tgt" || true)"
    cur_src="$(normalize_findmnt_source "$cur_src")"
    if [ "$cur_src" != "$src" ]; then
      warn "Remontando $tgt de $cur_src -> $src"
      umount -f "$tgt" || true
      mount --bind "$src" "$tgt"
    fi
    mount -o remount,bind,ro "$tgt"
  else
    mount --bind "$src" "$tgt"
    mount -o remount,bind,ro "$tgt"
  fi

  local opts; opts="$(findmnt -n -o OPTIONS --target "$tgt" || true)"
  if echo "$opts" | grep -qw ro; then
    ok "Bind RO: $src -> $tgt"
  else
    warn "RO não garantido em $tgt (opts: $opts)"
  fi
}

process_project(){
  local CLIENT="$1" PROJECT="$2"
  local PROJ_ROOT="/home/${CLIENT}/${PROJECT}"
  local SRC_DIR="${PROJ_ROOT}/src"
  [ -d "$SRC_DIR" ] || { warn "Sem src: $SRC_DIR (pulando)"; return 0; }

  local DEST_BASE="${RBROOT}/${CLIENT}/${PROJECT}"
  local DEST_DUMPS="${DEST_BASE}/dumps"
  local DEST_SRC="${DEST_BASE}/src"
  mkdir -p "$DEST_DUMPS" "$DEST_SRC"

  # dump
  local ENV_PATH="${SRC_DIR}/.env"
  local DUMP_FILE="${DEST_DUMPS}/dump.sql"
  if [ -f "$ENV_PATH" ]; then
    local DB_CONNECTION; DB_CONNECTION="$(get_env_kv "$ENV_PATH" "DB_CONNECTION" | tr '[:upper:]' '[:lower:]')"
    if [[ "$DB_CONNECTION" == "mysql" || "$DB_CONNECTION" == "mariadb" ]]; then
      local DB_HOST DB_PORT DB_NAME DB_USER DB_PASS
      DB_HOST="$(get_env_kv "$ENV_PATH" "DB_HOST")";  [ -z "$DB_HOST" ] && DB_HOST="mysql"
      DB_PORT="$(get_env_kv "$ENV_PATH" "DB_PORT")";  [ -z "$DB_PORT" ] && DB_PORT="3306"
      DB_NAME="$(get_env_kv "$ENV_PATH" "DB_DATABASE")"
      DB_USER="$(get_env_kv "$ENV_PATH" "DB_USERNAME")"
      DB_PASS="$(get_env_kv "$ENV_PATH" "DB_PASSWORD")"

      if [ -n "$DB_NAME" ] && [ -n "$DB_USER" ]; then
        dump_mysql_sql "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "${DB_PASS:-}" "$DUMP_FILE" || true
      else
        warn "$CLIENT/$PROJECT: .env incompleto para dump."
      fi
    else
      warn "$CLIENT/$PROJECT: DB_CONNECTION='$DB_CONNECTION' não suportado para dump automático."
    fi
  else
    warn "$CLIENT/$PROJECT: sem .env; sem dump."
  fi

  # bind src
  ensure_bind_ro "$SRC_DIR" "$DEST_SRC" || true

  echo "----------------------------------------"
  echo "Projeto: ${CLIENT}/${PROJECT}"
  echo " - SRC        : $SRC_DIR"
  echo " - Espelho RO : $DEST_SRC"
  echo " - Dumps      : $DEST_DUMPS"
  echo " - Dump atual : $DUMP_FILE $( [ -f "$DUMP_FILE" ] && echo '(OK)' || echo '(não gerado)' )"
  echo "----------------------------------------"
}

require_root(){
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "Execute como root (sudo)."; exit 1;
  fi
}

main(){
  require_root
  b "==> mkrbackup — varrendo projetos em /home/*/*/src"
  mkdir -p "$RBROOT"

  shopt -s nullglob
  local found=0
  for SRC in /home/*/*/src; do
    [ -d "$SRC" ] || continue
    local PROJECT_DIR; PROJECT_DIR="$(dirname "$SRC")"
    local CLIENT; CLIENT="$(basename "$(dirname "$PROJECT_DIR")")"
    local PROJECT; PROJECT="$(basename "$PROJECT_DIR")"
    found=1
    process_project "$CLIENT" "$PROJECT"
  done
  shopt -u nullglob

  if [ "$found" -eq 0 ]; then
    warn "Nenhum projeto /home/<cliente>/<projeto>/src encontrado."
  else
    ok "Concluído."
  fi
}

main "$@"
