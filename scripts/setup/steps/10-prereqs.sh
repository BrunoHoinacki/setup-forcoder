# shellcheck shell=bash
need_root
apt_like >/dev/null || die "Somente Ubuntu/Debian (apt)."

# se Traefik estiver rodando, derruba pra recriar sem conflito
if command -v docker >/dev/null 2>&1; then
  if docker ps --format '{{.Names}}' | grep -q '^traefik$'; then
    warn "Traefik já está rodando. Derrubando para recriar..."
    (cd /opt/traefik 2>/dev/null && docker compose down) || true
  fi
fi

# portas 80/443 livres
b "==> Checando portas 80/443"
if ss -tulpn 2>/dev/null | grep -q ':80 '; then die "Porta 80 em uso por outro serviço."; fi
if ss -tulpn 2>/dev/null | grep -q ':443 '; then die "Porta 443 em uso por outro serviço."; fi
ok "Portas livres."
