#!/usr/bin/env bash
set -euo pipefail

# Requer: ROOT, SRC_DIR, DB_MODE, AUTO_PHP_PROFILE, PHP_PROFILE
# Saída: define PHP_PROFILE se AUTO_PHP_PROFILE=1 (min|full) e persiste no state.

if [[ "${AUTO_PHP_PROFILE:-1}" -ne 1 ]]; then
  b "==> Perfil PHP definido manualmente (${PHP_PROFILE})."
  save_state
  exit 0
fi

b "==> Detectando perfil PHP pelo composer.json"

DETECTED="min"

COMPOSER_JSON="${SRC_DIR}/composer.json"
if [[ -f "${COMPOSER_JSON}" ]]; then
  # Sinais fortes de necessidade do intl:
  # - ext-intl explícito
  # - pacote Filament
  # - symfony/intl
  if grep -Eq '"ext-intl" *:' "${COMPOSER_JSON}"; then
    DETECTED="full"
  elif grep -Eq '"filament/[^"]+"' "${COMPOSER_JSON}"; then
    DETECTED="full"
  elif grep -Eq '"symfony/intl" *:' "${COMPOSER_JSON}"; then
    DETECTED="full"
  fi
else
  warn "composer.json não encontrado para detecção — usando 'min'."
fi

PHP_PROFILE="${DETECTED}"
ok "Perfil PHP detectado: ${PHP_PROFILE}"
export PHP_PROFILE
save_state
