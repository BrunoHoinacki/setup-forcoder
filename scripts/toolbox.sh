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

# ===== Config =====
ROOT="/opt/setup-forcoder"
REPO_OWNER="BrunoHoinacki"
REPO_NAME="setup-forcoder"
REPO_BRANCH="main"
GH_TARBALL_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_BRANCH}.tar.gz"

# ===== Funções internas =====
have(){ command -v "$1" >/dev/null 2>&1; }

wait_apt(){
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock)
  local msg_shown=0
  while :; do
    local busy=0
    for L in "${locks[@]}"; do
      if fuser "$L" >/dev/null 2>&1; then busy=1; fi
    done
    if [ $busy -eq 0 ]; then break; fi
    if [ $msg_shown -eq 0 ]; then y "⏳ APT em uso; aguardando liberar..."; msg_shown=1; fi
    sleep 3
  done
}

ensure_basics(){
  local need=()
  have curl || need+=(curl)
  have unzip || need+=(unzip)
  have tar || need+=(tar)
  [ -f /etc/ssl/certs/ca-certificates.crt ] || need+=(ca-certificates)

  if [ ${#need[@]} -gt 0 ]; then
    export DEBIAN_FRONTEND=noninteractive
    wait_apt
    apt-get update -y
    apt-get install -y --no-install-recommends "${need[@]}"
  fi
}

# ===== Bootstrap =====
if [ ! -d "$ROOT/scripts" ]; then
  b "==> SetupForcoder não encontrado. Preparando ambiente inicial..."

  ensure_basics
  mkdir -p "$ROOT"

  # baixa última versão do GitHub (branch main)
  tmp_tar="/tmp/${REPO_NAME}.tar.gz"
  curl -fsSL "$GH_TARBALL_URL" -o "$tmp_tar"
  tar -xzf "$tmp_tar" -C /tmp

  # detecta diretório extraído (qualquer nome-*-main)
  SRC_DIR="$(find /tmp -maxdepth 1 -type d -name "${REPO_NAME}-*-${REPO_BRANCH}" -print -quit)"
  if [ -z "${SRC_DIR:-}" ]; then
    SRC_DIR="$(find /tmp -maxdepth 1 -type d -name "*-${REPO_BRANCH}" -print -quit)"
  fi
  [ -n "${SRC_DIR:-}" ] || die "Não foi possível localizar pasta extraída do tarball."

  cp -R "${SRC_DIR}/." "$ROOT/"

  # permissões de execução
  if [ -d "$ROOT/scripts" ]; then
    chmod +x "$ROOT/scripts/"*.sh 2>/dev/null || true
    chmod +x "$ROOT/scripts"/*/*.sh 2>/dev/null || true
  fi

  # atalho opcional
  if [ ! -e /usr/local/bin/setupforcoder ]; then
    ln -s "$ROOT/scripts/toolbox.sh" /usr/local/bin/setupforcoder || true
  fi

  b "==> SetupForcoder instalado em $ROOT"
fi

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
