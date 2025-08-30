#!/usr/bin/env bash
set -euo pipefail

# =============== mkbackup.sh =======================
# Cria ZIP contendo SOMENTE o conteúdo de /home/<cliente>/<projeto>/src,
# e, se MySQL/MariaDB, adiciona dump.sql.gz na raiz do ZIP.
# Compatível com mkclient.sh (espera dump.sql ou dump.sql.gz em src/).
# Saída: /opt/backups/<cliente>/<projeto>/<cliente>_<projeto>_YYYYmmdd-HHMM.zip
# ===================================================

b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo "  [OK] $*"; }
warn(){ echo "  [!] $*"; }
die(){ echo "  [ERR] $*" >&2; exit 1; }
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo su)."; }

ensure_zip(){
  if command -v zip >/dev/null 2>&1; then return; fi
  warn "'zip' não encontrado — instalando..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null && apt-get install -y zip >/dev/null
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache zip >/dev/null
  elif command -v yum >/dev/null 2>&1; then
    yum install -y zip >/dev/null
  else
    die "Não consegui instalar 'zip' automaticamente."
  fi
  ok "zip instalado."
}

# Lê KEY=VALUE (última ocorrência não comentada), removendo aspas de borda
get_env_kv(){
  # uso: get_env_kv ARQUIVO CHAVE
  local file="$1" key="$2" raw
  [ -f "$file" ] || { echo ""; return 0; }
  raw="$(grep -E "^[[:space:]]*${key}=" "$file" | grep -v '^[[:space:]]*#' | tail -n1 | cut -d= -f2- | sed 's/[[:space:]]*$//')"
  raw="${raw%\"}"; raw="${raw#\"}"; raw="${raw%\'}"; raw="${raw#\'}"
  printf '%s' "$raw"
}

# Descobre container do banco: "mysql" OU "mariadb"
detect_db_container(){
  if docker ps --format '{{.Names}}' | grep -qx mysql; then
    echo "mysql"; return 0
  fi
  if docker ps --format '{{.Names}}' | grep -qx mariadb; then
    echo "mariadb"; return 0
  fi
  echo ""; return 1
}

dump_mysql_gz(){
  # Usa mysqldump/mariadb-dump no container detectado; gera dump.sql.gz
  local db_host="$1" db_port="$2" db_name="$3" db_user="$4" db_pass="$5" out_gz="$6"
  local ctn=""; ctn="$(detect_db_container || true)"
  if [ -z "$ctn" ]; then
    warn "Nenhum container 'mysql' ou 'mariadb' rodando — pulando dump."
    return 1
  fi

  # Flags específicas
  local MYSQL_FLAGS=(--single-transaction --routines --events --triggers --set-gtid-purged=OFF --column-statistics=0)
  local MARIA_FLAGS=(--single-transaction --routines --events --triggers)

  local AUTH_ARGS=(-u"$db_user" -h "$db_host" -P "${db_port:-3306}")
  local ENVV=()
  if [ -n "${db_pass:-}" ]; then ENVV=(-e "MYSQL_PWD=$db_pass"); fi

  local SSL_FLAG="--ssl-mode=DISABLED"

  set +e
  docker exec "${ENVV[@]}" -i "$ctn" mysqldump "${AUTH_ARGS[@]}" $SSL_FLAG "${MYSQL_FLAGS[@]}" "$db_name" | gzip -9 > "$out_gz"
  local rc=$?
  if [ $rc -ne 0 ]; then
    docker exec "${ENVV[@]}" -i "$ctn" mariadb-dump "${AUTH_ARGS[@]}" "${MARIA_FLAGS[@]}" "$db_name" | gzip -9 > "$out_gz"
    rc=$?
  fi
  set -e

  if [ $rc -ne 0 ]; then
    warn "Falha ao gerar dump do banco."
    return 1
  fi

  ok "Dump gerado: $(basename "$out_gz")"
  return 0
}

# ------- Inputs -------
need_root
read -rp "Cliente (ex.: cliente1): " CLIENT
read -rp "Projeto (ex.: site): " PROJECT

ROOT="/home/${CLIENT}/${PROJECT}"
SRC_DIR="${ROOT}/src"
[ -d "$SRC_DIR" ] || die "Diretório de código não encontrado: $SRC_DIR"

read -rp "Destino do backup [1=local /opt/backups | 2=custom path] (default 1): " DEST_OPT
DEST_OPT="${DEST_OPT:-1}"
if [[ "$DEST_OPT" = "2" ]]; then
  read -rp "Caminho ABSOLUTO do diretório destino: " DEST_DIR
  [ -n "${DEST_DIR:-}" ] || die "Destino vazio."
else
  DEST_DIR="/opt/backups/${CLIENT}/${PROJECT}"
fi
mkdir -p "$DEST_DIR"

# Excluir pesos (opcional)
read -rp "Excluir pastas pesadas (vendor,node_modules,.git)? [Y/n]: " EXC
EXC="${EXC:-Y}"
EXCLUDES=()
if [[ "$EXC" =~ ^[Yy]$ ]]; then
  EXCLUDES+=(--exclude='./vendor' --exclude='./node_modules' --exclude='./.git')
fi

TS="$(date +%Y%m%d-%H%M)"
OUT_ZIP="${DEST_DIR}/${CLIENT}_${PROJECT}_${TS}.zip"

ensure_zip
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STAGE="${TMP}/stage"
mkdir -p "$STAGE"

# Copia APENAS o conteúdo de src/ para staging (mantém estrutura e ocultos)
( cd "$SRC_DIR" && tar -cf - . "${EXCLUDES[@]}" ) | ( cd "$STAGE" && tar -xf - )

# ------- Verifica DB e gera dump.sql.gz se MySQL/MariaDB -------
ENV_PATH="${SRC_DIR}/.env"
DB_KIND="<unknown>"; DUMP_DONE=0

if [ -f "$ENV_PATH" ]; then
  DB_CONNECTION="$(get_env_kv "$ENV_PATH" "DB_CONNECTION" | tr '[:upper:]' '[:lower:]')"
  DB_KIND="$DB_CONNECTION"

  if [[ "$DB_CONNECTION" == "mysql" || "$DB_CONNECTION" == "mariadb" ]]; then
    DB_HOST="$(get_env_kv "$ENV_PATH" "DB_HOST")";    [ -z "$DB_HOST" ] && DB_HOST="mysql"
    DB_PORT="$(get_env_kv "$ENV_PATH" "DB_PORT")";    [ -z "$DB_PORT" ] && DB_PORT="3306"
    DB_NAME="$(get_env_kv "$ENV_PATH" "DB_DATABASE")"
    DB_USER="$(get_env_kv "$ENV_PATH" "DB_USERNAME")"
    DB_PASS="$(get_env_kv "$ENV_PATH" "DB_PASSWORD")"

    if [ -n "$DB_NAME" ] && [ -n "$DB_USER" ]; then
      dump_mysql_gz "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "${DB_PASS:-}" "${STAGE}/dump.sql.gz" && DUMP_DONE=1 || true
    else
      warn "Variáveis de DB incompletas no .env — sem dump."
    fi
  elif [[ "$DB_CONNECTION" == "sqlite" ]]; then
    ok "Projeto SQLite — nenhum dump adicional necessário."
  else
    warn "DB_CONNECTION='${DB_CONNECTION:-}' não suportado para dump automático."
  fi
else
  warn "Sem ${ENV_PATH}; não foi possível detectar o tipo de DB."
fi

# ------- Empacota ZIP final (somente conteúdo de src/ + dump.sql.gz se existir) -------
( cd "$STAGE" && zip -qr "$OUT_ZIP" . )
ok "Backup gerado: $OUT_ZIP"

echo
b "Resumo"
echo " - Fonte       : $SRC_DIR"
echo " - Destino     : $OUT_ZIP"
echo " - DB          : ${DB_KIND}"
echo " - dump.sql.gz : $([ "$DUMP_DONE" -eq 1 ] && echo 'incluído' || echo 'não incluído')"