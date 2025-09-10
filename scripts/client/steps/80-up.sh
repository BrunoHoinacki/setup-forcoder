b "==> Build e subida (${MODE})"
if [[ "${MODE}" = "compose" ]]; then
  ( cd "${ROOT}" && docker compose build php )
  ( cd "${ROOT}" && docker compose up -d )
else
  ( cd "${ROOT}" && docker build -t "${CLIENT}_${PROJECT}_php:latest" -f "$(basename "${STACK_FILE%/*}")/$(basename "${PHP_SQLITE_DF}")" . ) >/dev/null 2>&1 || true
  ( cd "${ROOT}" && docker build -t "${CLIENT}_${PROJECT}_php:latest" -f "$(basename "${PHP_MYSQL_DF}")" . ) >/dev/null 2>&1 || true
  ( cd "${ROOT}" && docker stack deploy -c "${STACK_FILE}" "${STACK_NAME}" )
fi

trigger_acme_and_wait "${DOMAIN}" || true
save_state
