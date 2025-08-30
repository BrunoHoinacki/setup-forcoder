# shellcheck shell=bash
b "==> Parâmetros"

read -rp "E-mail para Let's Encrypt: " LE_EMAIL
[ -n "${LE_EMAIL:-}" ] || die "E-mail é obrigatório."

read -rp "Domínio do dashboard do Traefik (ex.: infra.seu-dominio.com.br): " DASH_DOMAIN
[ -n "${DASH_DOMAIN:-}" ] || die "Domínio do dashboard é obrigatório."

CF_USE_PROXY=0
CF_DNS_API_TOKEN=""
if ask_yes_no "Vai usar Cloudflare PROXY (nuvem laranja) para o dashboard (${DASH_DOMAIN})? [y/N]:" "N"; then
  CF_USE_PROXY=1
  read -rp "Cloudflare API Token (DNS-01) [vazio = HTTP-01]: " CF_DNS_API_TOKEN
fi

ACME_MODE="http01"
if [[ $CF_USE_PROXY -eq 1 && -n "$CF_DNS_API_TOKEN" ]]; then
  ACME_MODE="dns01"
fi

echo "Canonical do site:"
echo "  [1] non-www (exemplo.com -> canonical)"
echo "  [2] www (www.exemplo.com -> canonical)"
read -rp "Escolha [1/2] (default 1): " CAN
CAN="${CAN:-1}"
[[ "$CAN" =~ ^[12]$ ]] || die "Escolha inválida."
CANONICAL_MW="www-to-root"; [ "$CAN" = "2" ] && CANONICAL_MW="root-to-www"
RESOLVED_CANONICAL="${CANONICAL_MW}@docker"

read -rp "Usuário BasicAuth do dashboard (default admin): " DASH_USER
DASH_USER="${DASH_USER:-admin}"
read -rsp "Senha BasicAuth do dashboard: " DASH_PW
echo
[ -n "${DASH_PW:-}" ] || die "Senha é obrigatória."
HTPASSWD_ESCAPED="$(htpasswd_line "$DASH_USER" "$DASH_PW" | sed 's/\$/$$/g')"

read -rp "Subir MySQL central + phpMyAdmin agora? [Y/n]: " USE_DB_STACK
USE_DB_STACK="${USE_DB_STACK:-Y}"

MYSQL_ROOT_PASSWORD=""
if [[ "${USE_DB_STACK^^}" == "Y" ]]; then
  read -rsp "Senha do root do MySQL (vazio=gerar): " MYSQL_ROOT_PASSWORD
  echo
  if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
    MYSQL_ROOT_PASSWORD="$(openssl rand -base64 18 | tr -d '=+/')"
    warn "Gerada senha root do MySQL: ${MYSQL_ROOT_PASSWORD}"
  fi
fi

# exporta para os próximos passos
export LE_EMAIL DASH_DOMAIN CF_DNS_API_TOKEN ACME_MODE CANONICAL_MW RESOLVED_CANONICAL
export DASH_USER DASH_PW HTPASSWD_ESCAPED USE_DB_STACK MYSQL_ROOT_PASSWORD
