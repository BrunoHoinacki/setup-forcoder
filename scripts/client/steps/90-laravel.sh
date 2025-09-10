#!/usr/bin/env bash
set -euo pipefail

# Ajustes Laravel em Compose/Swarm usando run_in_php (lib.sh)
if [[ -f "${SRC_DIR}/artisan" ]]; then
  b "==> Detectado Laravel — composer/otimizações/migrations"

  # SQLite: arquivo
  if [[ "$DB_MODE" = "sqlite" ]]; then
    mkdir -p "${SRC_DIR}/database"
    [[ -f "${SRC_DIR}/database/database.sqlite" ]] || touch "${SRC_DIR}/database/database.sqlite"
    chown -R "${CLIENT}:${CLIENT}" "${SRC_DIR}/database"
  fi

  # composer install (respeita COMPOSER_WITH_DEV; pula se vendor/ + lock)
  if [[ -d "${SRC_DIR}/vendor" && -f "${SRC_DIR}/composer.lock" ]]; then
    ok "vendor/ presente; pulando composer install."
  else
    if [[ "${COMPOSER_WITH_DEV:-0}" -eq 1 ]]; then
      b "composer install (DEV)…"
      run_in_php "composer install --prefer-dist --no-interaction"
    else
      b "composer install (PROD --no-dev)…"
      run_in_php "composer install --no-dev --prefer-dist --no-interaction"
    fi
  fi

  # chave/optimize/storage link
  run_in_php "php artisan key:generate --force || true"
  run_in_php "composer dump-autoload -o || true"
  run_in_php "php artisan optimize || true"
  run_in_php "php artisan storage:link || true"

  # viewsmysql:make
  if [[ "${NEED_VIEWSMYSQL:-0}" -eq 1 ]]; then
    run_in_php 'php artisan list --ansi | grep -q "viewsmysql:make" && php artisan viewsmysql:make || echo "viewsmysql:make não encontrado."'
  fi
  # menu:make
  if [[ "${RUN_MENU_MAKE:-0}" -eq 1 ]]; then
    run_in_php 'php artisan list --ansi | grep -q "menu:make" && php artisan menu:make || echo "menu:make não encontrado."'
  fi

  # migrations/seed (pula se dump importado)
  if [[ "$DB_MODE" = "mysql" && "${DUMP_IMPORTED:-0}" = "1" ]]; then
    warn "Dump importado — pulando migrate/seed."
  else
    [[ "${RUN_MIGRATE:-0}" -eq 1 ]] && run_in_php "php artisan migrate --force" || true
    [[ "${RUN_SEED:-0}"    -eq 1 ]] && run_in_php "php artisan db:seed --force" || true
  fi

  # permissões
  run_in_php "chown -R www-data:www-data storage bootstrap/cache && chmod -R ug+rw storage bootstrap/cache" || true
else
  warn "artisan não encontrado — pulando ajustes Laravel."
fi

save_state
