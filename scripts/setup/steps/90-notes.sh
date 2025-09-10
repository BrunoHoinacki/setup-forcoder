# shellcheck shell=bash
# Step 90 — notas finais pós-deploy

# ===== Logging isolado do step =====
STEP_NO="90"
STEP_NAME="notes"
STEP_LOG_DIR="/var/log/setup-forcoder-logs/setup"
mkdir -p "$STEP_LOG_DIR" 2>/dev/null || true
STEP_LOG_FILE="${STEP_LOG_DIR}/step${STEP_NO}-${STEP_NAME}_$(date +%F_%H%M%S).log"

# salva FDs e duplica saída apenas dentro deste step
exec 3>&1 4>&2
exec > >(stdbuf -oL -eL tee -a "$STEP_LOG_FILE") 2>&1
echo "---- BEGIN STEP ${STEP_NO} (${STEP_NAME}) $(date -Iseconds) on $(hostname) ----"
echo "Log file: $STEP_LOG_FILE"

b "==> Notas finais"

DOMAIN="${TRAEFIK_DASHBOARD_DOMAIN:-<domínio não definido>}"
ACME="${ACME_MODE:-http01}"
DB_ON="${USE_DB_STACK:-N}"

# tenta descobrir IP público (melhor esforço, sem quebrar o step)
PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "$PUBLIC_IP" ] || PUBLIC_IP="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
[ -n "$PUBLIC_IP" ] || PUBLIC_IP="<IP da VPS>"

cat <<EOF
 - Aponte o DNS A/AAAA de ${DOMAIN} -> IP da VPS (${PUBLIC_IP}).
 - Dashboard (use o caminho): https://${DOMAIN}/dashboard/  (login: ${DASH_USER:-admin})
 - A raiz https://${DOMAIN}/ retorna 404 por design; use /dashboard/.
EOF

if [[ "${DB_ON^^}" == "Y" ]]; then
  cat <<EOF
 - phpMyAdmin: https://${DOMAIN}/phpmyadmin/  (atenção à barra final).
 - Senha root do MySQL: ${MYSQL_ROOT_PASSWORD:-<n/a>}
EOF
fi

if [[ "${ACME}" = "dns01" ]]; then
  echo " - Certificados via DNS-01 (Cloudflare). Pode manter a nuvem laranja ligada."
else
  echo " - Certificados via HTTP-01. Deixe o DNS direto (nuvem cinza) durante a emissão."
fi

cat <<'EOF'
 - Após emitir, o Traefik começa a servir HTTPS em ~5s.
 - Logs ACME/SSL: docker service logs -f traefik_traefik | egrep 'acme|lego|challenge|cloudflare|certificate'
EOF

echo "---- END STEP ${STEP_NO} (${STEP_NAME}) $(date -Iseconds) ----"
# restaura FDs originais
exec 1>&3 2>&4
exec 3>&- 4>&-
