# shellcheck shell=bash
b "==> Instalando Docker + dependências"
install_docker_portable

if command -v ufw >/dev/null 2>&1; then
  ufw allow 22,80,443/tcp >/dev/null 2>&1 || true
  warn "Se o UFW estava desativado, habilite manualmente: ufw enable"
fi

if [ -n "${SUDO_USER:-}" ] && command -v usermod >/dev/null 2>&1; then
  if ! id -nG "$SUDO_USER" | grep -qw docker; then
    usermod -aG docker "$SUDO_USER" || true
    warn "Adicionado '$SUDO_USER' ao grupo docker (relogin necessário)."
  fi
fi
