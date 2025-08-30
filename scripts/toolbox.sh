#!/usr/bin/env bash
set -euo pipefail

# ===== Helpers =====
b(){ echo -e "\033[1;36m$*\033[0m"; }   # azul claro
g(){ echo -e "\033[1;32m$*\033[0m"; }   # verde
y(){ echo -e "\033[1;33m$*\033[0m"; }   # amarelo
r(){ echo -e "\033[1;31m$*\033[0m"; }   # vermelho
die(){ r "[ERR] $*"; exit 1; }
pause(){ echo; read -n1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."; echo; }

# executa comando e mantém a tela (sem matar o toolbox se o comando falhar)
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

ROOT="/opt/devops-stack"
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo su)."; }
need_root

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

  b "==> STACK TOOLBOX"
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
  g " 12) Desfazer binds (rbackupunbind.sh)"
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
    12) run "bash '$ROOT/scripts/rbackupunbind.sh'" ;;
    0)  exit 0 ;;
    *)  r "Opção inválida."; sleep 1 ;;
  esac
done
