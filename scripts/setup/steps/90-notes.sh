# shellcheck shell=bash
b "==> Notas finais"

echo " - Aponte o DNS A/AAAA de ${DASH_DOMAIN} -> IP da VPS."
echo " - Dashboard (use o caminho): https://${DASH_DOMAIN}/dashboard/  (login: ${DASH_USER})"
echo " - Raiz https://${DASH_DOMAIN}/ retorna 404 por design; use /dashboard/."
if [[ "${USE_DB_STACK^^}" == "Y" ]]; then
  echo " - phpMyAdmin: https://${DASH_DOMAIN}/phpmyadmin/  (atenção à barra final)."
  echo " - Senha root do MySQL: ${MYSQL_ROOT_PASSWORD}"
fi

if [[ "$ACME_MODE" = "dns01" ]]; then
  echo " - Certificados via DNS-01 (Cloudflare). Pode manter a nuvem laranja ligada."
else
  echo " - Certificados via HTTP-01. Deixe o DNS CINZA (DNS only) até emitir."
fi

echo " - Após emitir, o Traefik começa a servir HTTPS em ~5s."
echo " - Logs ACME/SSL: docker logs -f traefik | egrep 'acme|lego|challenge|cloudflare|certificate'"
