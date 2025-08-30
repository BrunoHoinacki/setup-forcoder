#!/usr/bin/env bash
set -euo pipefail

# ----------- UI helpers -----------
b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo -e "  [OK] $*"; }
warn(){ echo -e "  [!] $*"; }
die(){ echo -e "  [ERR] $*" >&2; exit 1; }

# ----------- guards -----------
need_root() { [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo su)."; }
apt_like()  { command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; }

# ----------- pkg manager (Ubuntu usa apt; Debian usa apt-get) -----------
detect_pkg(){
  . /etc/os-release 2>/dev/null || true
  case "${ID:-}" in
    ubuntu) echo "apt" ;;
    debian) echo "apt-get" ;;
    *)      command -v apt-get >/dev/null 2>&1 && echo "apt-get" || echo "apt" ;;
  esac
}
PKG="$(detect_pkg)"

pkg_update(){
  export DEBIAN_FRONTEND=noninteractive
  if [ "$PKG" = "apt" ]; then
    apt update -y
  else
    apt-get update -y
  fi
}

pkg_install(){
  export DEBIAN_FRONTEND=noninteractive
  if [ "$PKG" = "apt" ]; then
    apt install -y "$@"
  else
    apt-get install -y "$@"
  fi
}

# ----------- utils -----------
ask_yes_no() {
  local prompt="$1" default="${2:-N}"
  local ans; read -rp "$prompt " ans || true
  ans="${ans:-$default}"
  ans="$(echo "$ans" | tr '[:upper:]' '[:lower:]')"
  [[ "$ans" = "y" || "$ans" = "yes" || "$ans" = "s" || "$ans" = "sim" ]]
}

htpasswd_line() {
  local user="$1" pass="$2"
  if command -v htpasswd >/dev/null 2>&1; then
    htpasswd -nbB "$user" "$pass"
  else
    warn "apache2-utils não presente; gerando hash APR1 (menos recomendado)."
    local hash
    hash=$(openssl passwd -apr1 "$pass")
    echo "${user}:${hash}"
  fi
}

ensure_known_hosts_github() {
  mkdir -p /root/.ssh
  touch /root/.ssh/known_hosts
  chmod 700 /root/.ssh
  chmod 644 /root/.ssh/known_hosts
  ssh-keyscan -t ed25519,ecdsa,rsa github.com >> /root/.ssh/known_hosts 2>/dev/null || true
}

install_docker_portable() {
  export DEBIAN_FRONTEND=noninteractive
  pkg_update
  pkg_install ca-certificates curl gnupg lsb-release apache2-utils ufw openssh-client >/dev/null

  systemctl disable --now apache2 2>/dev/null || true
  systemctl disable --now nginx   2>/dev/null || true

  if command -v docker >/dev/null 2>&1; then
    ok "Docker já presente."
    return 0
  fi

  install -m 0755 -d /etc/apt/keyrings
  local KEYRING="/etc/apt/keyrings/docker.gpg"

  . /etc/os-release
  local OS_ID="${ID,,}"
  local CODENAME="${VERSION_CODENAME:-}"
  local DOCKER_OS="" DOCKER_CODE=""

  case "$OS_ID" in
    ubuntu)
      DOCKER_OS="ubuntu"
      case "$CODENAME" in
        focal|jammy|noble|mantic) DOCKER_CODE="$CODENAME" ;;
        *) DOCKER_CODE="jammy"; warn "Ubuntu '$CODENAME' não listado no repo Docker; usando 'jammy'." ;;
      esac
      ;;
    debian)
      DOCKER_OS="debian"
      case "$CODENAME" in
        bullseye|bookworm) DOCKER_CODE="$CODENAME" ;;
        trixie|testing|sid|unstable) DOCKER_CODE="bookworm"; warn "Repo Docker ainda não tem '$CODENAME'; usando 'bookworm'." ;;
        *) DOCKER_CODE="bookworm"; warn "Debian '$CODENAME' não listado; usando 'bookworm'." ;;
      esac
      ;;
    *) die "Somente Ubuntu/Debian são suportados (ID='$OS_ID').";;
  esac

  echo "  -> Detectado: OS=${DOCKER_OS}, codename=${CODENAME}, repo_codename=${DOCKER_CODE}"

  if [ ! -f "$KEYRING" ]; then
    curl -fsSL "https://download.docker.com/linux/${DOCKER_OS}/gpg" | gpg --dearmor -o "$KEYRING"
    chmod a+r "$KEYRING" || true
  fi

  rm -f /etc/apt/sources.list.d/docker.list
  echo "deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING] https://download.docker.com/linux/${DOCKER_OS} ${DOCKER_CODE} stable" > /etc/apt/sources.list.d/docker.list

  if ! pkg_update; then
    warn "Falha ao atualizar com repo oficial do Docker. Instalando pacotes da distro (docker.io)."
    pkg_install docker.io docker-compose-plugin || die "Falha ao instalar docker.io pela distro."
    systemctl enable --now docker
    ok "Docker instalado (docker.io)."
    return 0
  fi

  if ! pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    warn "Falha nos pacotes do repo oficial. Instalando docker.io da distro."
    pkg_install docker.io docker-compose-plugin || die "Falha ao instalar docker.io pela distro."
  fi

  systemctl enable --now docker
  ok "Docker instalado."
}
