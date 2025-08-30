#!/usr/bin/env bash
set -euo pipefail

# ===== Helpers =====
b(){ echo -e "\033[1;36m$*\033[0m"; }   # azul claro
g(){ echo -e "\033[1;32m$*\033[0m"; }   # verde
y(){ echo -e "\033[1;33m$*\033[0m"; }   # amarelo
r(){ echo -e "\033[1;31m$*\033[0m"; }   # vermelho
die(){ r "[ERR] $*"; exit 1; }

need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo su)."; }
need_root

pause(){ echo; read -n1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."; echo; }
run(){
  local cmd="$*"
  echo
  set +e
  bash -lc "$cmd"
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    r "Comando terminou com código $rc"
  fi
  pause
}

# ===== Resolve ROOT =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || echo "/opt/setup-forcoder")"

# ===== Sanity check =====
need_file(){ [ -f "$1" ] || die "Arquivo não encontrado: $1"; }

if [ ! -d "$ROOT/scripts" ]; then
  r "Diretório de scripts não encontrado em: $ROOT/scripts"
  echo
  y "Instale com 1 comando:"
  echo "  curl -fsSL https://raw.githubusercontent.com/BrunoHoinacki/setup-forcoder/main/scripts/install.sh | sudo bash"
  exit 1
fi

need_file "$ROOT/scripts/setup.sh"
need_file "$ROOT/scripts/mkclient.sh"
need_file "$ROOT/scripts/delclient.sh"
need_file "$ROOT/scripts/delallclients.sh"
need_file "$ROOT/scripts/generaldocker.sh"
need_file "$ROOT/scripts/generalgit.sh"
need_file "$ROOT/scripts/mkbackup.sh"
need_file "$ROOT/scripts/resetsetup.sh"
# opcional:
# [ -f "$ROOT/scripts/rbackupunbind.sh" ] || true

# ===== Menu =====
while true; do
  clear
  cat <<'BANNER'
██████╗ ███████╗██╗   ██╗ ██████╗ ██████╗ ███████╗
██╔══██╗██╔════╝██║   ██║██╔═══██╗██╔══██╗██╔════╝
██║  ██║█████╗  ██║   ██║██║   ██║██████╔╝███████╗
██║  ██║██╔══╝  ╚██╗ ██╔╝██║   ██║██╔═══╝ ╚════██║
██████╔╝███████╗ ╚████╔╝ ╚██████╔╝██║     ███████║
╚═════╝ ╚══════╝  ╚═══╝   ╚═════╝ ╚═╝     ╚══════╝
BANNER

  b "==> SETUP FORCODER <=="
  b "by Bruno Hoinacki"
  b "https://github.com/BrunoHoinacki/setup-forcoder"
  echo -e "\033[90m──────────────────────────────────────────────\033[0m"
  echo ""
  g "  1) Setup inicial da VPS (Traefik + redes + opcional MySQL/PMA)"
  g "  2) Provisionar cliente/projeto (mkclient.sh)"
  y "  3) Remover projeto (delclient.sh)"
  y "  4) Remover TODOS os projetos (delallclients.sh)"
  echo ""
  g "  5) Utilitários Docker (generaldocker.sh)"
  g "  6) Utilitários Git (generalgit.sh)"
  g "  7) Backup de projeto (mkbackup.sh)"
  echo ""
  g "  8) Recriar/sobe Traefik (docker compose up -d)"
  g "  9) Logs do Traefik (access.json tail -f)  [Ctrl+C para voltar]"
  y " 10) Reset da infra base (resetsetup.sh)"
  g " 11) Status dos containers (docker ps)"
  g " 12) Desfazer binds (rbackupunbind.sh) [opcional]"
  r "  0) Sair"
  echo ""
  echo -e "\033[90m──────────────────────────────────────────────\033[0m"
  echo ""
  read -rp "Selecione uma opção: " op

  case "$op" in
    1)  run "bash '$ROOT/scripts/setup.sh'" ;;
    2)  run "bash '$ROOT/scripts/mkclient.sh'" ;;
    3)  run "bash '$ROOT/scripts/delclient.sh'" ;;
    4)  run "bash '$ROOT/scripts/delallclients.sh'" ;;
    5)  run "bash '$ROOT/scripts/generaldocker.sh'" ;;
    6)  run "bash '$ROOT/scripts/generalgit.sh'" ;;
    7)  run "bash '$ROOT/scripts/mkbackup.sh'" ;;
    8)  run "(cd /opt/traefik && docker compose up -d)" ;;
    9)  echo; echo "Pressione Ctrl+C para voltar ao menu..."; tail -f /opt/traefik/logs/access.json ;;
    10) run "bash '$ROOT/scripts/resetsetup.sh'" ;;
    11) echo; docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'; pause ;;
    12) if [ -f "$ROOT/scripts/rbackupunbind.sh" ]; then
          run "bash '$ROOT/scripts/rbackupunbind.sh'"
        else
          y "Script opcional ausente: $ROOT/scripts/rbackupunbind.sh"; pause
        fi ;;
    0)  exit 0 ;;
    *)  r "Opção inválida."; sleep 1 ;;
  esac
done
