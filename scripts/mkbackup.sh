#!/usr/bin/env bash
set -euo pipefail

# =============== mkbackup.sh =======================
# Cria ZIP contendo SOMENTE o conteúdo de /home/<cliente>/<projeto>/src,
# e, se MySQL/MariaDB, adiciona dump.sql.gz na raiz do ZIP.
# Compatível com Compose e Swarm.
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
  local file="$1" key="$2" raw
  [ -f "$file" ] || { echo ""; return 0; }
  raw="$(grep -E "^[[:space:]]*${key}=" "$file" | grep -v '^[[:space:]]*#' | tail -n1 | cut -d= -f2- | sed 's/[[:space:]]*$//')"
  raw="${raw%\"}"; raw="${raw#\"}"; raw="${raw%\'}"; raw="${raw#\'}"
  printf '%s' "$raw"
}

is_swarm_active(){ docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q '^active$'; }

# Encontra um container (task) RUNNING para um service que termine com _mysql ou _mariadb
find_db_task_container(){
  local project="$1"
  local svc
  for svc in "${project}_mysql" "${project}_mariadb"; do
    if docker service ls --format '{{.Name}}' | grep -qx "$svc"; then
      local tid cid
      tid="$(docker service ps --filter 'desired-state=running' --format '{{.ID}}' "$svc" | head -n1 || true)"
      [ -z "$tid" ] && continue
      cid="$(docker inspect --format '{{.Status.ContainerStatus.ContainerID}}' "$tid" 2>/dev/null || true)"
      [ -n "$cid" ] && { echo "$cid"; return 0; }
    fi
  done
  # fallback: tenta qualquer container com label de service mysql/mariadb
  docker ps -q --filter "name=_mysql\." --filter "status=running" | head -n1 && return 0
  docker ps -q --filter "name=_mariadb\." --filter "status=running" | head -n1 && return 0
  return 1
}

# Descobre container do banco em Compose (nome exato 'mysql' ou 'mariadb'), com fallback por imagem
detect_db_container_compose(){
  if docker ps --format '{{.Names}}' | grep -qx mysql; then echo "mysql"; return 0; fi
  if docker ps --format '{{.Names}}' | grep -qx mariadb; then echo "mariadb"; return 0; fi
  # fallback fraco por imagem
  local cid
  cid="$(docker ps -q --filter 'ancestor=mysql' --filter 'status=running' | head -n1 || true)"
  [ -n "$cid" ] && { echo "$cid"; return 0; }
  cid="$(docker ps -q --filter 'ancestor=mariadb' --filter 'status=running' | head -n1 || true)"
  [ -n "$cid" ] && { echo "$cid"; return 0; }
  echo ""; return 1
}

dump_mysql_gz(){
  # Preferência: executar mysqldump/mariadb-dump **dentro do container** (Compose ou Swarm).
  # Se não achar container, tenta no host se cliente estiver instalado.
  local project="$1" db_host="$2" db_port="$3" db_name="$4" db_user="$5" db_pass="$6" out_gz="$7"

  local ctn=""
  if is_swarm_active; then
    ctn="$(find_db_task_container "$project" || true)"
  else
    ctn="$(detect_db_container_compose || true)"
  fi

  local AUTH_ARGS=(-u"$db_user" -h "$db_host" -P "${db_port:-3306}")
  local ENVV=()
  [ -n "${db_pass:-}" ] && ENVV=(-e "MYSQL_PWD=$db_pass")

  local MYSQL_FLAGS=(--single-transaction --routines --events --triggers --set-gtid-purged=OFF --column-statistics=0)
  local MARIA_FLAGS=(--single-transaction --routines --events --triggers)
  local SSL_FLAG="--ssl-mode=DISABLED"

  if [ -n "$ctn" ]; then
    set +e
    docker exec "${ENVV[@]}" -i "$ctn" mysqldump "${AUTH_ARGS[@]}" $SSL_FLAG "${MYSQL_FLAGS[@]}" "$db_name" | gzip -9 > "$out_gz"
    local rc=$?
    if [ $rc -ne 0 ]; then
      docker exec "${ENVV[@]}" -i "$ctn" mariadb-dump "${AUTH_ARGS[@]}" "${MARIA_FLAGS[@]}" "$db_name" | gzip -9 > "$out_gz"
      rc=$?
    fi
    set -e
    if [ $rc -eq 0 ]; then ok "Dump (in-container) gerado: $(basename "$out_gz")"; return 0; fi
    warn "Falha ao gerar dump dentro do container ($ctn). Tentando via host..."
  fi

  # fallback via host: requer cliente instalado
  if command -v mysqldump >/dev/null 2>&1; then
    set +e
    MYSQL_PWD="${db_pass:-}" mysqldump "${AUTH_ARGS[@]}" $SSL_FLAG "${MYSQL_FLAGS[@]}" "$db_name" | gzip -9 > "$out_gz"
    local rc=$?
    set -e
    [ $rc -eq 0 ] && { ok "Dump (host) gerado: $(basename "$out_gz")"; return 0; }
  fi

  warn "Não foi possível gerar dump do banco."
  return 1
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
      dump_mysql_gz "$PROJECT" "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "${DB_PASS:-}" "${STAGE}/dump.sql.gz" && DUMP_DONE=1 || true
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
