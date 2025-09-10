#!/usr/bin/env bash
set -euo pipefail

ok "Stack online."
b "==> Resumo / Dicas"
echo "Diretório do projeto : ${ROOT}"
echo "Código-fonte         : ${SRC_DIR}"
echo "Deploy (MODE)        : ${MODE}"
[[ "${MODE}" = "compose" ]] && echo "Compose              : ${COMPOSE}"
[[ "${MODE}" = "swarm"   ]] && echo "Stack (yml)          : ${STACK_FILE}  (stack name: ${STACK_NAME})"
echo "PHP (container)      : ${PHP_VER}"
if [[ "${DB_MODE}" = "mysql" ]]; then
  echo "DB central (mysql)   : database=${DB_NAME} user=${DB_USER} pass=${DB_PASS}"
  echo "Dump esperado        : ${SRC_DIR}/dump.sql(.gz) — removido após import."
fi
echo
echo "Testes rápidos:"
if [[ "${MODE}" = "compose" ]]; then
  echo "  docker compose -f ${COMPOSE} ps"
  echo "  docker compose -f ${COMPOSE} logs -f nginx"
else
  echo "  docker service ls | grep '^${STACK_NAME}_'"
  echo "  docker service logs -f ${STACK_NAME}_nginx"
fi
echo "  curl -I https://${DOMAIN}"
echo
b "==> Execuções Laravel configuradas"
echo "Composer       : $( [[ ${COMPOSER_WITH_DEV:-0} -eq 1 ]] && echo "com dev" || echo "produção (--no-dev)" )"
echo "Migrate        : $( [[ ${RUN_MIGRATE:-0} -eq 1 ]] && echo "SIM" || echo "NÃO" )"
echo "Seed           : $( [[ ${RUN_SEED:-0} -eq 1 ]] && echo "SIM" || echo "NÃO" )"
echo "menu:make      : $( [[ ${RUN_MENU_MAKE:-0} -eq 1 ]] && echo "SIM" || echo "NÃO" )"
echo "views:mysql    : $( [[ ${NEED_VIEWSMYSQL:-0} -eq 1 ]] && echo "SIM" || echo "NÃO" )"
