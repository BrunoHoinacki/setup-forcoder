# shellcheck shell=bash
# Step 20 — coleta inputs, mostra resumo (inclui segredos) e pede confirmação forte.
# Depende das helpers do setup/lib.sh (b, warn, die, ask_yes_no, htpasswd_line).

b "==> Parâmetros"

read -rp "E-mail para Let's Encrypt: " LETSENCRYPT_EMAIL
[ -n "${LETSENCRYPT_EMAIL:-}" ] || die "E-mail é obrigatório."

read -rp "Domínio do dashboard do Traefik (ex.: infra.seu-dominio.com.br): " TRAEFIK_DASHBOARD_DOMAIN
[ -n "${TRAEFIK_DASHBOARD_DOMAIN:-}" ] || die "Domínio do dashboard é obrigatório."

CF_USE_PROXY=0
CF_DNS_API_TOKEN=""
if ask_yes_no "Vai usar Cloudflare PROXY (nuvem laranja) para o dashboard (${TRAEFIK_DASHBOARD_DOMAIN})? [y/N]:" "N"; then
  CF_USE_PROXY=1
  read -rp "Cloudflare API Token (DNS-01) [vazio = HTTP-01]: " CF_DNS_API_TOKEN
fi

# ACME mode: se proxy + token => dns01; caso contrário http01
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

read -rp "Usuário BasicAuth do dashboard (default admin): " DASH_USER
DASH_USER="${DASH_USER:-admin}"
# senha visível para evitar erro de colagem
read -rp "Senha BasicAuth do dashboard: " DASH_PW
[ -n "${DASH_PW:-}" ] || die "Senha é obrigatória."

# Gera a linha htpasswd e ESCAPA $ -> $$ para YAML/docker
HTPASSWD_ESCAPED="$(htpasswd_line "$DASH_USER" "$DASH_PW" | sed 's/\$/$$/g')"

read -rp "Subir MySQL central + phpMyAdmin agora? [Y/n]: " USE_DB_STACK
USE_DB_STACK="${USE_DB_STACK:-Y}"

MYSQL_ROOT_PASSWORD=""
if [[ "${USE_DB_STACK^^}" == "Y" ]]; then
  # senha visível para evitar erro de colagem
  read -rp "Senha do root do MySQL (vazio=gerar): " MYSQL_ROOT_PASSWORD
  if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      MYSQL_ROOT_PASSWORD="$(openssl rand -base64 18 | tr -d '=+/')"
    else
      MYSQL_ROOT_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -d '=+/' | cut -c1-24)"
    fi
    warn "Gerada senha root do MySQL: ${MYSQL_ROOT_PASSWORD}"
  fi
fi

TZ="America/Sao_Paulo"

echo
b "==> Resumo dos parâmetros (inclui segredos)"
cat <<EOF
Let's Encrypt e-mail      : ${LETSENCRYPT_EMAIL}
Dashboard domain          : ${TRAEFIK_DASHBOARD_DOMAIN}
Cloudflare proxy          : $([ $CF_USE_PROXY -eq 1 ] && echo "YES" || echo "NO")
ACME mode                 : ${ACME_MODE}
Canonical middleware      : ${CANONICAL_MW}  (encadeado via canonical@file)
BasicAuth user            : ${DASH_USER}
BasicAuth password (plain): ${DASH_PW}
Usar MySQL/phpMyAdmin     : ${USE_DB_STACK}
MySQL root password       : ${MYSQL_ROOT_PASSWORD:-<n/a>}
Timezone (Traefik)        : ${TZ}
EOF

INPUT_LOG_DIR="/var/log/setup-forcoder-logs/setup"
mkdir -p "$INPUT_LOG_DIR" 2>/dev/null || true
INPUT_LOG_FILE="${INPUT_LOG_DIR}/inputs_$(date +%F_%H%M%S).log"
{
  echo "---- INPUTS $(date -Iseconds) on $(hostname) ----"
  echo "LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}"
  echo "TRAEFIK_DASHBOARD_DOMAIN=${TRAEFIK_DASHBOARD_DOMAIN}"
  echo "CF_USE_PROXY=${CF_USE_PROXY}"
  echo "CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}"
  echo "ACME_MODE=${ACME_MODE}"
  echo "CANONICAL_MW=${CANONICAL_MW}"
  echo "DASH_USER=${DASH_USER}"
  echo "DASH_PW=${DASH_PW}"
  echo "USE_DB_STACK=${USE_DB_STACK}"
  echo "MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}"
  echo "TZ=${TZ}"
} >> "$INPUT_LOG_FILE"
echo "Resumo salvo em: $INPUT_LOG_FILE"

echo
read -rp "Digite CONFIRM para aplicar estes valores: " _OK
[[ "${_OK}" == "CONFIRM" ]] || die "Abortado pelo usuário."

# Exporta para os próximos passos (NOMES EXATOS usados no stack.yml!)
export LETSENCRYPT_EMAIL TRAEFIK_DASHBOARD_DOMAIN CF_DNS_API_TOKEN ACME_MODE CANONICAL_MW
export DASH_USER DASH_PW HTPASSWD_ESCAPED USE_DB_STACK MYSQL_ROOT_PASSWORD TZ
