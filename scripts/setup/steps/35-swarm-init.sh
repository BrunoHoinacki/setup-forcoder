# shellcheck shell=bash
b "==> Ativando Docker Swarm (se necessário)"

if ! command -v docker >/dev/null 2>&1; then
  die "Docker não está instalado. Rode o passo 30 antes."
fi

state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
if [ "$state" != "active" ]; then
  warn "Swarm não está ativo (estado=$state). Iniciando 'docker swarm init'..."
  docker swarm init || die "Falha ao iniciar o Docker Swarm."
else
  ok "Swarm já está ativo."
fi
