#!/usr/bin/env bash
set -euo pipefail

# Ajustes Laravel: composer, chave, otimizações, migrations/seed e permissões.
# Requer variáveis carregadas do state (ROOT, SRC_DIR, DB_MODE, etc.)
# e funções de lib.sh (b, ok, warn).

if [[ -f "${SRC_DIR}/artisan" ]]; then
  b "==> Detectado Laravel — composer/otimizações/migrations"

  # SQLite: garante arquivo
  if [[ "$DB_MODE" = "sqlite" ]]; then
    mkdir -p "${SRC_DIR}/database"
    [[ -f "${SRC_DIR}/database/database.sqlite" ]] || touch "${SRC_DIR}/database/database.sqlite"
    chown -R "${CLIENT}:${CLIENT}" "${SRC_DIR}/database"
  fi

  # composer install (respeita COMPOSER_WITH_DEV; pula se ZIP trouxe vendor/ + lock)
  if [[ -d "${SRC_DIR}/vendor" && -f "${SRC_DIR}/composer.lock" ]]; then
    ok "vendor/ presente; pulando composer install."
  else
    if [[ "${COMPOSER_WITH_DEV:-0}" -eq 1 ]]; then
      b "Executando composer install (com dev)…"
      ( cd "${ROOT}" && docker compose run --rm php composer install --prefer-dist --no-interaction )
    else
      b "Executando composer install (produção --no-dev)…"
      ( cd "${ROOT}" && docker compose run --rm php composer install --no-dev --prefer-dist --no-interaction )
    fi
  fi

  # chave + autoload + otimizações + storage link
  ( cd "${ROOT}" && docker compose run --rm php php artisan key:generate --force || true )
  ( cd "${ROOT}" && docker compose run --rm php composer dump-autoload -o || true )
  ( cd "${ROOT}" && docker compose run --rm php php artisan optimize || true )
  ( cd "${ROOT}" && docker compose run --rm php php artisan storage:link || true )

  # viewsmysql:make (opcional via NEED_VIEWSMYSQL)
  if [[ "${NEED_VIEWSMYSQL:-0}" -eq 1 ]]; then
    ( cd "${ROOT}" && docker compose run --rm php sh -lc 'php artisan list --ansi | grep -q "viewsmysql:make" && php artisan viewsmysql:make || echo "viewsmysql:make não encontrado."' ) || true
  fi

  # menu:make (opcional via RUN_MENU_MAKE)
  if [[ "${RUN_MENU_MAKE:-0}" -eq 1 ]]; then
    ( cd "${ROOT}" && docker compose run --rm php sh -lc 'php artisan list --ansi | grep -q "menu:make" && php artisan menu:make || echo "menu:make não encontrado."' ) || true
  fi

  # migrations/seed (pular se dump importado)
  if [[ "$DB_MODE" = "mysql" && "${DUMP_IMPORTED:-0}" = "1" ]]; then
    warn "Dump importado — pulando migrate/seed."
  else
    if [[ "${RUN_MIGRATE:-0}" -eq 1 ]]; then
      ( cd "${ROOT}" && docker compose run --rm php php artisan migrate --force ) || warn "Migrate falhou."
    fi
    if [[ "${RUN_SEED:-0}" -eq 1 ]]; then
      ( cd "${ROOT}" && docker compose run --rm php php artisan db:seed --force ) || warn "Seed falhou."
    fi
  fi

  # permissões
  ( cd "${ROOT}" && docker compose run --rm php sh -lc "chown -R www-data:www-data storage bootstrap/cache && chmod -R ug+rw storage bootstrap/cache" ) || true
else
  warn "artisan não encontrado — pulando ajustes Laravel."
fi

save_state
