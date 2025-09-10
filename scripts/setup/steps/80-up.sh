# shellcheck shell=bash
b "==> Subindo stack (Swarm)"
cd /opt/traefik

# derruba traefik antigo (compose) se existir
if docker ps --format '{{.Names}}' | grep -q '^traefik$'; then
  warn "Encontrado container 'traefik' (standalone). Removendo para evitar conflito de porta..."
  docker rm -f traefik || true
fi

docker stack deploy -c stack.yml traefik
ok "Stack 'traefik' implantada."

echo
docker service ls --format 'table {{.Name}}\t{{.Mode}}\t{{.Replicas}}\t{{.Ports}}' | sed '1!b;s/^/SERVICES\n/;'
