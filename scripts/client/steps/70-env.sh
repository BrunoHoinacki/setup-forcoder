ENV_PATH="${SRC_DIR}/.env"
b "==> Garantindo e ajustando ${ENV_PATH}"
if [[ -f "$ENV_PATH" ]]; then
  ok ".env já existe — será ajustado."
  adjust_env_existing "$ENV_PATH" "$DB_MODE"
else
  if [[ "$DB_MODE" = "sqlite" ]]; then
    cat > "$ENV_PATH" <<EOF
APP_ENV=production
APP_DEBUG=false
APP_URL=https://${DOMAIN}
APP_KEY=
SESSION_DRIVER=file
CACHE_STORE=file
QUEUE_CONNECTION=sync
LOG_CHANNEL=stack
LOG_LEVEL=info
SESSION_SECURE_COOKIE=true
TRUSTED_PROXIES=*
TRUSTED_HEADERS=X_FORWARDED_ALL
DB_CONNECTION=sqlite
DB_DATABASE=/var/www/html/database/database.sqlite
EOF
  else
    cat > "$ENV_PATH" <<EOF
APP_ENV=production
APP_DEBUG=false
APP_URL=https://${DOMAIN}
APP_KEY=
SESSION_DRIVER=file
CACHE_STORE=file
QUEUE_CONNECTION=sync
LOG_CHANNEL=stack
LOG_LEVEL=info
SESSION_SECURE_COOKIE=true
TRUSTED_PROXIES=*
TRUSTED_HEADERS=X_FORWARDED_ALL
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}
EOF
  fi
fi
chown "${CLIENT}:${CLIENT}" "$ENV_PATH"

save_state
