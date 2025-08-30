#!/usr/bin/env bash
set -euo pipefail

# ========= UI =========
b(){ echo -e "\033[1;36m$*\033[0m"; }   # azul claro
g(){ echo -e "\033[1;32m$*\033[0m"; }   # verde
y(){ echo -e "\033[1;33m$*\033[0m"; }   # amarelo
r(){ echo -e "\033[1;31m$*\033[0m"; }   # vermelho
die(){ r "[ERR] $*"; exit 1; }

# ========= Guardas =========
[ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root. Ex.:  curl -fsSL https://raw.githubusercontent.com/BrunoHoinacki/setup-forcoder/main/scripts/install.sh | sudo bash"

# ========= Config =========
ROOT="/opt/setup-forcoder"
REPO_OWNER="BrunoHoinacki"
REPO_NAME="setup-forcoder"
REPO_BRANCH="main"
GH_TARBALL_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_BRANCH}.tar.gz"

# ========= Helpers =========
have(){ command -v "$1" >/dev/null 2>&1; }

wait_apt() {
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock)
  local showed=0
  while :; do
    local busy=0
    for L in "${locks[@]}"; do
      if fuser "$L" >/dev/null 2>&1; then busy=1; fi
    done
    if [ $busy -eq 0 ]; then break; fi
    if [ $showed -eq 0 ]; then y "⏳ Aguardando o APT liberar..."; showed=1; fi
    sleep 3
  done
}

ensure_basics(){
  local need=()
  have curl  || need+=(curl)
  have tar   || need+=(tar)
  have unzip || need+=(unzip)
  [ -f /etc/ssl/certs/ca-certificates.crt ] || need+=(ca-certificates)

  if [ ${#need[@]} -gt 0 ]; then
    export DEBIAN_FRONTEND=noninteractive
    wait_apt
    apt-get update -y
    apt-get install -y --no-install-recommends "${need[@]}"
  fi
}

# ========= Bootstrap =========
b "==> Instalando SetupForcoder (root em $ROOT)..."
ensure_basics
mkdir -p "$ROOT"

tmp_tar="/tmp/${REPO_NAME}.tar.gz"
curl -fL --progress-bar "$GH_TARBALL_URL" -o "$tmp_tar"
tar -xzf "$tmp_tar" -C /tmp

# detecta pasta extraída (*-main)
SRC_DIR="$(find /tmp -maxdepth 1 -type d -name "${REPO_NAME}-*-${REPO_BRANCH}" -print -quit)"
if [ -z "${SRC_DIR:-}" ]; then
  SRC_DIR="$(find /tmp -maxdepth 1 -type d -name "*-${REPO_BRANCH}" -print -quit)"
fi
[ -n "${SRC_DIR:-}" ] || die "Não foi possível localizar a pasta extraída do tarball."

cp -R "${SRC_DIR}/." "$ROOT/"

# normaliza CRLF -> LF (evita 'unexpected end of file' em heredoc)
if [ -d "$ROOT/scripts" ]; then
  find "$ROOT/scripts" -type f -name '*.sh' -print0 2>/dev/null | xargs -0 -r sed -i 's/\r$//'
fi

# permissões executáveis
if [ -d "$ROOT/scripts" ]; then
  chmod +x "$ROOT/scripts/"*.sh 2>/dev/null || true
  chmod +x "$ROOT/scripts"/*/*.sh 2>/dev/null || true
fi

# atalho opcional
if [ ! -e /usr/local/bin/setupforcoder ]; then
  ln -s "$ROOT/scripts/toolbox.sh" /usr/local/bin/setupforcoder || true
fi

g "✔ SetupForcoder instalado em $ROOT"
echo

# ========= Garante TTY (quando rodou via pipe) =========
if [ -e /dev/tty ]; then
  exec </dev/tty >/dev/tty 2>&1
else
  y "Não foi possível anexar /dev/tty. Rode manualmente:"
  echo "  bash $ROOT/scripts/toolbox.sh"
  exit 0
fi

# ========= Executa o toolbox =========
exec bash "$ROOT/scripts/toolbox.sh"
