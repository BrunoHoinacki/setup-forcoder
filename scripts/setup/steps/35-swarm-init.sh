# shellcheck shell=bash
b "==> Ativando Docker Swarm (se necessário)"

if ! command -v docker >/dev/null 2>&1; then
  die "Docker não está instalado. Rode o passo 30 antes."
fi

state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
if [ "$state" = "active" ]; then
  ok "Swarm já está ativo."
  return 0
fi

warn "Swarm não está ativo (estado=${state:-desconhecido}). Iniciando 'docker swarm init'..."

# --- Descoberta do endereço a anunciar ---
ADDR="${SWARM_ADVERTISE_ADDR:-}"

pick_public_ip() {
  # Pega IP v4 público da interface de saída (descarta RFC1918, 100.64/10, 169.254/16 e loopback)
  local iface ips
  iface="$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1)"
  [ -z "$iface" ] && return 1
  mapfile -t ips < <(ip -4 addr show dev "$iface" | awk '/inet /{print $2}' | cut -d/ -f1)

  printf '%s\n' "${ips[@]}" \
    | grep -E -v '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|169\.254\.|127\.)' \
    | head -n1
}

if [ -z "$ADDR" ]; then
  ADDR="$(pick_public_ip || true)"
fi

attempt_init() {
  local a="$1"
  if [ -n "$a" ]; then
    b "Tentando: docker swarm init --advertise-addr ${a}"
    docker swarm init --advertise-addr "$a"
  else
    b "Tentando: docker swarm init (sem --advertise-addr)"
    docker swarm init
  fi
}

set +e
if attempt_init "$ADDR"; then
  set -e
  ok "Swarm iniciado com sucesso${ADDR:+ (advertise-addr=$ADDR)}."
  return 0
fi

# fallback: se falhar com o IP escolhido, tenta todos os IPv4 da interface default
iface="$(ip route show default 2>/dev/null | awk '{print $5}' | head -n1)"
mapfile -t ALL_IPS < <(ip -4 addr show dev "$iface" | awk '/inet /{print $2}' | cut -d/ -f1)

for ip in "${ALL_IPS[@]}"; do
  [ "$ip" = "$ADDR" ] && continue  # já tentado
  if attempt_init "$ip"; then
    set -e
    ok "Swarm iniciado com advertise-addr=${ip}."
    return 0
  fi
done

# último fallback: tentar sem advertise-addr
if attempt_init ""; then
  set -e
  ok "Swarm iniciado sem --advertise-addr."
  return 0
fi
set -e

die "Falha ao iniciar o Docker Swarm. Dica: export SWARM_ADVERTISE_ADDR=<SEU_IP_PUBLICO> e rode o setup novamente."
