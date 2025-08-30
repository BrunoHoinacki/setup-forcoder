b "==> Build da imagem PHP e subida da stack"
( cd "${ROOT}" && docker compose build php )
( cd "${ROOT}" && docker compose up -d )
trigger_acme_and_wait "${DOMAIN}" || true
save_state
