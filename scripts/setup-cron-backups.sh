#!/usr/bin/env bash
set -euo pipefail

# =============== setup-cron-backup.sh =================
# Configura agendamento de backups automáticos via cron
# ======================================================

b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo "  [OK] $*"; }
warn(){ echo "  [!] $*"; }
err(){ echo "  [ERR] $*"; }

need_root(){ 
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "Execute como root (sudo)."
    exit 1
  fi
}

show_help(){
  b "Uso: $0 [opções]"
  echo
  echo "Configura agendamento de backups automáticos via cron"
  echo
  echo "Opções:"
  echo "  -h, --help        Mostra esta ajuda"
  echo "  -r, --remove      Remove agendamento existente"
  echo "  -s, --status      Mostra status atual"
  echo
  echo "Exemplos:"
  echo "  $0                # Configura backup diário às 2h"
  echo "  $0 -r             # Remove agendamento"
  echo "  $0 -s             # Mostra status"
}

get_script_dir(){
  cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
  pwd -P
}

# Verifica se o script de backup existe
check_backup_script(){
  local script_dir
  script_dir="$(get_script_dir)"
  local backup_script="${script_dir}/auto-backup.sh"
  
  if [ ! -f "$backup_script" ]; then
    err "Script de backup não encontrado: $backup_script"
    exit 1
  fi
  
  # Torna executável
  chmod +x "$backup_script"
}

# Adiciona entrada no crontab
add_cron_entry(){
  local schedule="$1"
  local command="$2"
  local comment="$3"
  
  # Remove entradas existentes com o mesmo comentário
  remove_cron_entry "$comment"
  
  # Adiciona nova entrada
  local tmp_cron
  tmp_cron="$(mktemp)"
  trap 'rm -f "$tmp_cron"' EXIT
  
  # Exporta crontab atual
  crontab -l > "$tmp_cron" 2>/dev/null || true
  
  # Adiciona comentário e comando
  echo "# $comment" >> "$tmp_cron"
  echo "$schedule $command" >> "$tmp_cron"
  
  # Instala nova crontab
  crontab "$tmp_cron"
  
  ok "Agendamento adicionado: $schedule $command"
}

# Remove entrada do crontab pelo comentário
remove_cron_entry(){
  local comment="$1"
  
  local tmp_cron
  tmp_cron="$(mktemp)"
  trap 'rm -f "$tmp_cron"' EXIT
  
  # Exporta crontab atual
  crontab -l > "$tmp_cron" 2>/dev/null || true
  
  # Remove entradas com o comentário
  local new_cron
  new_cron="$(mktemp)"
  local in_comment_block=false
  
  while IFS= read -r line || [ -n "$line" ]; do
    # Se linha é comentário de início do nosso bloco
    if [ "$line" = "# $comment" ]; then
      in_comment_block=true
      continue
    fi
    
    # Se estamos em um bloco de comentário nosso e a próxima linha é o comando
    if [ "$in_comment_block" = true ] && [[ "$line" != "#"* ]]; then
      in_comment_block=false
      continue  # Pula esta linha (o comando)
    fi
    
    # Se não é parte do nosso bloco, mantém
    if [ "$in_comment_block" = false ]; then
      echo "$line" >> "$new_cron"
    fi
  done < "$tmp_cron"
  
  # Instala crontab modificada
  if [ -s "$new_cron" ]; then
    crontab "$new_cron"
  else
    crontab -r 2>/dev/null || true
  fi
  
  ok "Agendamento removido: $comment"
}

# Mostra status do crontab
show_cron_status(){
  b "=== Status do Agendamento de Backups ==="
  
  if crontab -l >/dev/null 2>&1; then
    local tmp_cron
    tmp_cron="$(mktemp)"
    trap 'rm -f "$tmp_cron"' EXIT
    
    crontab -l > "$tmp_cron" 2>/dev/null || true
    
    local found=false
    while IFS= read -r line || [ -n "$line" ]; do
      if [[ "$line" == *"auto-backup.sh"* ]]; then
        echo "$line"
        found=true
      elif [[ "$line" == "# Backup automático"* ]]; then
        echo "$line"
        found=true
      fi
    done < "$tmp_cron"
    
    if [ "$found" = false ]; then
      echo "Nenhum agendamento de backup encontrado."
    fi
  else
    echo "Nenhum crontab configurado."
  fi
}

# Configura backup diário
setup_daily_backup(){
  local script_dir
  script_dir="$(get_script_dir)"
  local backup_script="${script_dir}/auto-backup.sh"
  
  # Verifica script
  check_backup_script
  
  # Adiciona ao crontab (diariamente às 2h da manhã)
  local schedule="0 2 * * *"
  local command="$backup_script >> /var/log/auto-backup-cron.log 2>&1"
  local comment="Backup automático diário (setup-forcoder)"
  
  add_cron_entry "$schedule" "$command" "$comment"
  
  ok "Backup automático configurado para executar diariamente às 2h da manhã."
  echo "Logs serão salvos em: /var/log/auto-backup-cron.log"
  echo "Backups serão salvos em: /opt/backups/"
  echo "Backups antigos (mais de 7 dias) serão automaticamente removidos."
}

main(){
  need_root
  
  local action="setup"
  
  # Processa argumentos
  while [[ $# -gt 0 ]]; do
    case $1 in
      -r|--remove)
        action="remove"
        shift
        ;;
      -s|--status)
        action="status"
        shift
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
  
  case $action in
    setup)
      setup_daily_backup
      ;;
    remove)
      remove_cron_entry "Backup automático diário (setup-forcoder)"
      ok "Agendamento de backup removido."
      ;;
    status)
      show_cron_status
      ;;
  esac
}

main "$@"
