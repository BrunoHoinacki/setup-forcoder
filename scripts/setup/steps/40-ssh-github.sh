# shellcheck shell=bash
b "==> SSH para GitHub"

export DEBIAN_FRONTEND=noninteractive
# usar os helpers do lib.sh
pkg_update >/dev/null 2>&1 || true
pkg_install openssh-client >/dev/null 2>&1 || true

mkdir -p /root/.ssh && chmod 700 /root/.ssh
KEY="/root/.ssh/id_ed25519"; PUB="${KEY}.pub"

if [[ -f "$KEY" && -f "$PUB" ]]; then
  ok "Chave SSH existente: ${PUB}"
else
  read -rp "E-mail para comentar na chave SSH (ex.: voce@empresa.com): " SSH_EMAIL
  [[ -n "${SSH_EMAIL:-}" ]] || die "E-mail é obrigatório para gerar a chave SSH."
  ssh-keygen -t ed25519 -C "$SSH_EMAIL" -f "$KEY" -N '' </dev/null
  ok "Chave SSH gerada em ${KEY}"
fi

eval "$(ssh-agent -s)" >/dev/null
ssh-add "$KEY" >/dev/null 2>&1 || true
ensure_known_hosts_github

b "==> Copie a chave SSH pública e cadastre no GitHub:"
echo "https://github.com/settings/keys"
echo "----------------------------------------------------------------"
cat "$PUB"
echo "----------------------------------------------------------------"
read -rp "Depois de adicionar a chave no GitHub, pressione ENTER para testar..."

while true; do
  set +e
  OUT="$(ssh -T -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$KEY" git@github.com 2>&1)"
  RC=$?
  set -e
  if echo "$OUT" | grep -qi "successfully authenticated"; then
    ok "Conexão SSH com GitHub OK."
    break
  else
    warn "Ainda não autenticou no GitHub."
    echo "$OUT"
    read -rp "Ajuste no GitHub e ENTER para tentar novamente..." _
  fi
done
