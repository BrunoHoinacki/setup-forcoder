#!/usr/bin/env bash
set -euo pipefail

# =============== delallclients.sh =================
# Percorre /home/<cliente>/<projeto> e remove TODOS os projetos:
#  - MODE=compose: docker compose down --remove-orphans --volumes
#  - MODE=swarm  : docker stack rm <stack> (aguarda remover)
#  - rm -rf /home/<cliente>/<projeto>
#  - (opcional) DROP DATABASE + DROP USER no MySQL central
#
# Flags:
#   --yes               não perguntar confirmações (modo não interativo)
#   --drop-mysql        já habilita drop de DB/USER para todos
#   --dry-run           apenas mostra o que faria, sem executar
#   --only-client=X     processa apenas /home/X/*
#   --exclude-client=X  ignora /home/X/*
#
# Segurança:
#  - só remove caminhos tipo /home/<cliente>/<projeto>
#  - confirma "DELETE ALL" por padrão
#  - valida nomes de DB/USER antes de dropar
# ==================================================

b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo "  [OK] $*"; }
warn(){ echo "  [!] $*"; }
die(){ echo "  [ERR] $*" >&2; exit 1; }
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo su)."; }

sanitize_name(){
  local s
  s="$(echo -n "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g')"
  echo -n "$s"
}

sanitize_stack(){
  local s="$1"
  s="$(echo -n "$s" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--\+/-/g' | sed 's/^-//;s/-$//')"
  printf '%s' "${s:0:48}"
}

from_env(){
  # Lê KEY=VALUE (última ocorrência não comentada); remove aspas de borda
  local file="$1" key="$2" raw
  [ -f "$file" ] || return 1
  raw="$(grep -E "^[[:space:]]*${key}=" "$file" | grep -v '^[[:space:]]*#' | tail -n1 | cut -d= -f2- | sed 's/[[:space:]]*$//')"
  raw="${raw%\"}"; raw="${raw#\"}"; raw="${raw%\'}"; raw="${raw#\'}"
  printf '%s' "$raw"
}

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

swarm_wait_stack_gone(){
  local stack="$1" t=0 timeout=90
  while [ $t -lt $timeout ]; do
    if ! docker stack services "$stack" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    t=$((t+2))
  done
  return 1
}

MYSQL_READY=0
MYSQL_ROOT_PASSWORD=""
MYSQL_DROP_ALL=0
YES=0
DRY=0
ONLY_CLIENT=""
EXCLUDE_CLIENT=""

# separador robusto (Unit Separator)
SEP=$'\x1F'

for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    --drop-mysql) MYSQL_DROP_ALL=1 ;;
    --dry-run) DRY=1 ;;
    --only-client=*) ONLY_CLIENT="${arg#*=}" ;;
    --exclude-client=*) EXCLUDE_CLIENT="${arg#*=}" ;;
    *) die "Flag desconhecida: $arg" ;;
  esac
done

need_root

# Detecta MySQL central (container 'mysql') e carrega senha
if docker ps --format '{{.Names}}' | grep -qx mysql && [ -f /opt/traefik/.env ]; then
  # shellcheck disable=SC1091
  . /opt/traefik/.env || true
  if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then
    MYSQL_READY=1
    MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
  else
    warn "MYSQL_ROOT_PASSWORD ausente em /opt/traefik/.env — DROP automático indisponível."
  fi
else
  warn "Container 'mysql' inativo OU /opt/traefik/.env ausente — DROP automático indisponível."
fi

# Coleta todos os projetos candidatos: /home/<cliente>/<projeto>
declare -a ITEMS=()
for cdir in /home/*; do
  [ -d "$cdir" ] || continue
  client="$(basename "$cdir")"

  # Filtros
  [ -n "$ONLY_CLIENT" ] && [ "$client" != "$ONLY_CLIENT" ] && continue
  [ -n "$EXCLUDE_CLIENT" ] && [ "$client" = "$EXCLUDE_CLIENT" ] && continue

  # Ignora perfis comuns do sistema
  case "$client" in
    root|ubuntu|ec2-user|debian|centos) continue ;;
  esac

  for pdir in "$cdir"/*; do
    [ -d "$pdir" ] || continue
    if [ -f "$pdir/docker-compose.yml" ] || [ -f "$pdir/stack.yml" ] || [ -d "$pdir/src" ]; then
      ITEMS+=("${client}${SEP}$(basename "$pdir")${SEP}${pdir}")
    fi
  done
done

if [ "${#ITEMS[@]}" -eq 0 ]; then
  b "Nenhum projeto encontrado em /home/*/*."
  exit 0
fi

# Prévia
b "Projetos encontrados para remoção:"
for it in "${ITEMS[@]}"; do
  IFS="$SEP" read -r c p path <<<"$it"
  mode="compose"; [ -f "$path/stack.yml" ] && mode="swarm"
  echo " - $c / $p  ($path)  [${mode}]"
done

# Confirmação global
if [ "$YES" -ne 1 ]; then
  echo
  read -rp "CONFIRME digitando 'DELETE ALL' para remover TODOS os projetos listados: " CONFIRM
  [ "$CONFIRM" = "DELETE ALL" ] || die "Cancelado."
fi

# Caso MYSQL_DROP_ALL não tenha sido forçado por flag, pergunta (se houver MySQL)
if [ "$MYSQL_DROP_ALL" -ne 1 ] && [ "$YES" -ne 1 ] && [ "$MYSQL_READY" -eq 1 ]; then
  echo
  read -rp "Dropar também TODOS os bancos/usuários correspondentes no MySQL central? [y/N]: " ANS
  [[ "${ANS:-N}" =~ ^[Yy]$ ]] && MYSQL_DROP_ALL=1
fi

# Função: deduz DB_NAME/DB_USER
derive_db(){
  local client="$1" project="$2" src="$3"
  local db_from_env=0 db_name="" db_user="" db_conn="" env_path="${src}/.env"

  if [ -f "$env_path" ]; then
    db_name="$(from_env "$env_path" DB_DATABASE || true)"
    db_user="$(from_env "$env_path" DB_USERNAME || true)"
    db_conn="$(from_env "$env_path" DB_CONNECTION || true)"
    if [ "${db_conn:-}" = "mysql" ] && [ -n "${db_name:-}" ]; then
      db_from_env=1
    fi
  fi

  if [ "$db_from_env" -eq 1 ]; then
    printf "%s%s%s\n" "${db_name}" "$SEP" "${db_user:-"u_${client}_${project}"}"
  else
    local sdb suser
    sdb="$(sanitize_name "${client}_${project}")"
    suser="$(sanitize_name "u_${client}_${project}")"
    printf "%s%s%s\n" "${sdb}" "$SEP" "${suser}"
  fi
}

mysql_drop(){
  local db="$1" user="$2"
  guard_dbname "$db"
  guard_username "$user"
  docker exec -i mysql mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL || warn "  - Falha ao dropar DB/USER (seguindo)."
DROP DATABASE IF EXISTS \`${db}\`;
DROP USER IF EXISTS '${user}'@'%';
FLUSH PRIVILEGES;
SQL
  ok "  - DB \`${db}\` e USER '${user}' processados."
}

# Execução por item
TOTAL=0
for it in "${ITEMS[@]}"; do
  IFS="$SEP" read -r CLIENT PROJECT ROOT <<<"$it"
  SRC_DIR="${ROOT}/src"
  COMPOSE="${ROOT}/docker-compose.yml"
  STACK_FILE="${ROOT}/stack.yml"
  STATE="${ROOT}/.provision/state.env"

  MODE="compose"
  [ -f "$STACK_FILE" ] && MODE="swarm"

  STACK_NAME=""
  if [ -f "$STATE" ]; then
    # shellcheck disable=SC1090
    . "$STATE" || true
  fi
  [ -z "${STACK_NAME:-}" ] && STACK_NAME="$(sanitize_stack "${CLIENT}-${PROJECT}")"

  # Deriva DB info
  IFS="$SEP" read -r DB_NAME DB_USER <<<"$(derive_db "$CLIENT" "$PROJECT" "$SRC_DIR")"

  b "Removendo: $CLIENT / $PROJECT (${MODE})"
  echo " - Path    : $ROOT"
  echo " - DB alvo : $DB_NAME (user: $DB_USER)"

  if [ "$DRY" -eq 1 ]; then
    ok "[dry-run] pular execução real"
    echo
    TOTAL=$((TOTAL+1))
    continue
  fi

  # 1) Derrubar stack/containers
  if [ "$MODE" = "swarm" ]; then
    b "  - docker stack rm ${STACK_NAME}"
    set +e
    docker stack rm "$STACK_NAME"
    set -e
    swarm_wait_stack_gone "$STACK_NAME" || warn "  - Timeout aguardando remoção da stack."
  else
    if [ -f "$COMPOSE" ]; then
      b "  - docker compose down --remove-orphans --volumes"
      ( cd "$ROOT" && docker compose down --remove-orphans --volumes ) || warn "    Falha ao derrubar via compose."
    else
      for S in php nginx; do
        CNAME="${CLIENT}_${PROJECT}_${S}"
        if docker ps -a --format '{{.Names}}' | grep -qx "$CNAME"; then
          warn "  - Removendo container solto: $CNAME"
          docker rm -f "$CNAME" || true
        fi
      done
    fi
  fi

  # 2) Drop MySQL (opcional)
  if [ "$MYSQL_DROP_ALL" -eq 1 ] && [ "$MYSQL_READY" -eq 1 ]; then
    mysql_drop "$DB_NAME" "$DB_USER"
  fi

  # 3) Remover pasta
  if [[ "$ROOT" == /home/*/* && "$ROOT" != "/home/" ]]; then
    b "  - Removendo pasta do projeto..."
    rm -rf --one-file-system --preserve-root "$ROOT"
    ok "  - Pasta removida: $ROOT"
  else
    warn "  - Guardrail: caminho inválido p/ rm -rf ($ROOT) — ignorado."
  fi

  echo
  TOTAL=$((TOTAL+1))
done

b "Concluído. Projetos processados: $TOTAL"
if [ "$MYSQL_DROP_ALL" -eq 1 ] && [ "$MYSQL_READY" -eq 1 ]; then
  echo "Obs.: DB/USER do MySQL central foram processados para todos."
fi
