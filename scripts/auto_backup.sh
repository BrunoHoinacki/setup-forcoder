#!/usr/bin/env bash
set -euo pipefail

# =============== auto-backup.sh =======================
# Backup automático para todos os projetos em /home/*/*/
# Este script pode ser agendado via cron para backups regulares
# Logs são salvos em /var/log/auto-backup.log
# ======================================================

b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo "  [OK] $*"; }
warn(){ echo "  [!] $*"; }
err(){ echo "  [ERR] $*"; }
log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}"; }

need_root(){ 
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "Execute como root (sudo)."
    exit 1
  fi
}

# Configurações padrão (podem ser sobrescritas por variáveis de ambiente)
BACKUP_DIR="${BACKUP_DIR:-/opt/backups}"
LOG_FILE="${LOG_FILE:-/var/log/auto-backup.log}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

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

# Exclui backups antigos com base em RETENTION_DAYS
cleanup_old_backups(){
  local client="$1" project="$2"
  local backup_path="${BACKUP_DIR}/${client}/${project}"
  
  if [ -d "$backup_path" ]; then
    find "$backup_path" -name "${client}_${project}_*.zip" -type f -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true
    log "Backups antigos removidos para ${client}/${project} (mantidos últimos ${RETENTION_DAYS} dias)"
  fi
}

# Cria backup para um projeto específico
backup_project(){
  local client="$1" project="$2"
  local src_dir="/home/${client}/${project}/src"
  
  # Verifica se o diretório de código existe
  if [ ! -d "$src_dir" ]; then
    warn "Diretório de código não encontrado: $src_dir"
    log "ERRO: Diretório de código não encontrado: $src_dir"
    return 1
  fi
  
  # Cria diretório de destino
  local dest_dir="${BACKUP_DIR}/${client}/${project}"
  mkdir -p "$dest_dir"
  
  # Timestamp para o backup
  local ts="$(date +%Y%m%d-%H%M)"
  local out_zip="${dest_dir}/${client}_${project}_${ts}.zip"
  
  # Verifica se zip está instalado
  if ! command -v zip >/dev/null 2>&1; then
    warn "'zip' não encontrado"
    log "ERRO: 'zip' não encontrado"
    return 1
  fi
  
  # Cria diretório temporário
  local tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  local stage="${tmp}/stage"
  mkdir -p "$stage"
  
  # Copia APENAS o conteúdo de src/ para staging (mantém estrutura e ocultos)
  # Exclui pastas pesadas por padrão
  ( cd "$src_dir" && tar -cf - . --exclude='./vendor' --exclude='./node_modules' --exclude='./.git' ) | ( cd "$stage" && tar -xf - )
  
  # Verifica DB e gera dump.sql.gz se MySQL/MariaDB
  local env_path="${src_dir}/.env"
  local db_kind="<unknown>"
  local dump_done=0
  
  if [ -f "$env_path" ]; then
    local db_connection
    db_connection="$(get_env_kv "$env_path" "DB_CONNECTION" | tr '[:upper:]' '[:lower:]')"
    db_kind="$db_connection"
    
    if [[ "$db_connection" == "mysql" || "$db_connection" == "mariadb" ]]; then
      local db_host db_port db_name db_user db_pass
      db_host="$(get_env_kv "$env_path" "DB_HOST")";    [ -z "$db_host" ] && db_host="mysql"
      db_port="$(get_env_kv "$env_path" "DB_PORT")";    [ -z "$db_port" ] && db_port="3306"
      db_name="$(get_env_kv "$env_path" "DB_DATABASE")"
      db_user="$(get_env_kv "$env_path" "DB_USERNAME")"
      db_pass="$(get_env_kv "$env_path" "DB_PASSWORD")"
      
      if [ -n "$db_name" ] && [ -n "$db_user" ]; then
        dump_mysql_gz "$db_host" "$db_port" "$db_name" "$db_user" "${db_pass:-}" "${stage}/dump.sql.gz" && dump_done=1 || true
      else
        warn "Variáveis de DB incompletas no .env — sem dump."
        log "WARNING: Variáveis de DB incompletas no .env para ${client}/${project} — sem dump"
      fi
    elif [[ "$db_connection" == "sqlite" ]]; then
      ok "Projeto SQLite — nenhum dump adicional necessário."
    else
      warn "DB_CONNECTION='${db_connection:-}' não suportado para dump automático."
      log "WARNING: DB_CONNECTION='${db_connection:-}' não suportado para dump automático para ${client}/${project}"
    fi
  else
    warn "Sem ${env_path}; não foi possível detectar o tipo de DB."
    log "WARNING: Sem ${env_path} para ${client}/${project}; não foi possível detectar o tipo de DB"
  fi
  
  # Empacota ZIP final (somente conteúdo de src/ + dump.sql.gz se existir)
  ( cd "$stage" && zip -qr "$out_zip" . )
  ok "Backup gerado: $out_zip"
  log "Backup gerado: $out_zip (DB: ${db_kind}, dump: $([ "$dump_done" -eq 1 ] && echo 'incluído' || echo 'não incluído'))"
  
  # Limpa backups antigos
  cleanup_old_backups "$client" "$project"
  
  # Remove diretório temporário
  rm -rf "$tmp"
  trap - EXIT
}

# Backup para todos os projetos
backup_all_projects(){
  log "Iniciando backup automático para todos os projetos"
  
  local found=0
  shopt -s nullglob
  for src in /home/*/*/src; do
    [ -d "$src" ] || continue
    local project_dir
    project_dir="$(dirname "$src")"
    local client
    client="$(basename "$(dirname "$project_dir")")"
    local project
    project="$(basename "$project_dir")"
    
    found=1
    log "Processando projeto: ${client}/${project}"
    
    backup_project "$client" "$project" || {
      log "ERRO: Falha ao fazer backup de ${client}/${project}"
      continue
    }
  done
  shopt -u nullglob
  
  if [ "$found" -eq 0 ]; then
    warn "Nenhum projeto /home/<cliente>/<projeto>/src encontrado."
    log "WARNING: Nenhum projeto encontrado para backup"
  else
    ok "Backup automático concluído."
    log "Backup automático concluído com sucesso"
  fi
}

# Backup para projeto específico
backup_specific_project(){
  local client="$1"
  local project="$2"
  
  log "Iniciando backup para projeto específico: ${client}/${project}"
  
  if [ ! -d "/home/${client}/${project}/src" ]; then
    err "Projeto não encontrado: /home/${client}/${project}/src"
    log "ERRO: Projeto não encontrado: /home/${client}/${project}/src"
    exit 1
  fi
  
  backup_project "$client" "$project" || {
    log "ERRO: Falha ao fazer backup de ${client}/${project}"
    exit 1
  }
  
  ok "Backup concluído para ${client}/${project}."
  log "Backup concluído para ${client}/${project}"
}

show_help(){
  b "Uso: $0 [opções]"
  echo
  echo "Opções:"
  echo "  -a, --all                 Backup de todos os projetos (padrão)"
  echo "  -c, --client CLIENT       Cliente específico"
  echo "  -p, --project PROJECT     Projeto específico"
  echo "  -h, --help                Mostra esta ajuda"
  echo
  echo "Variáveis de ambiente:"
  echo "  BACKUP_DIR      Diretório de backup (padrão: /opt/backups)"
  echo "  LOG_FILE        Arquivo de log (padrão: /var/log/auto-backup.log)"
  echo "  RETENTION_DAYS  Dias para manter backups (padrão: 7)"
  echo
  echo "Exemplos:"
  echo "  $0                        # Backup de todos os projetos"
  echo "  $0 -c cliente1 -p site    # Backup de projeto específico"
  echo "  BACKUP_DIR=/tmp/backups $0 # Backup em diretório personalizado"
}

main(){
  need_root
  
  local client=""
  local project=""
  local all=true
  
  # Processa argumentos
  while [[ $# -gt 0 ]]; do
    case $1 in
      -a|--all)
        all=true
        shift
        ;;
      -c|--client)
        client="$2"
        all=false
        shift 2
        ;;
      -p|--project)
        project="$2"
        all=false
        shift 2
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        err "Opção desconhecida: $1"
        show_help
        exit 1
        ;;
    esac
  done
  
  # Valida parâmetros
  if [ "$all" = false ]; then
    if [ -z "$client" ] || [ -z "$project" ]; then
      err "Cliente e projeto devem ser especificados juntos"
      show_help
      exit 1
    fi
  fi
  
  # Garante que o diretório de log exista
  mkdir -p "$(dirname "$LOG_FILE")"
  
  # Executa backup
  if [ "$all" = true ]; then
    backup_all_projects
  else
    backup_specific_project "$client" "$project"
  fi
}

main "$@"
