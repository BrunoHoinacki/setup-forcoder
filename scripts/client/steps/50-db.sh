DB_PASS=""; DB_NAME=""; DB_USER=""; MYSQL_ROOT_PASSWORD=""; DUMP_IMPORTED=0

if [[ "$DB_MODE" = "mysql" ]]; then
  if [[ -f /opt/traefik/.env ]]; then . /opt/traefik/.env || true; fi
  [[ -n "${MYSQL_ROOT_PASSWORD:-}" ]] || die "MYSQL_ROOT_PASSWORD não encontrado em /opt/traefik/.env."
  docker ps --format '{{.Names}}' | grep -qx mysql || die "Container 'mysql' não está rodando."

  DB_NAME="$(echo "${CLIENT}_${PROJECT}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g' | cut -c1-64)"
  DB_USER="$(echo "u_${CLIENT}_${PROJECT}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g' | cut -c1-32)"
  DB_PASS="$(openssl rand -base64 18 | tr -d '=+/' )"

  b "==> Criando schema/usuário no MySQL central"
  docker exec -i mysql mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL

  DUMP_FILE=""
  [[ -f "${SRC_DIR}/dump.sql.gz" ]] && DUMP_FILE="${SRC_DIR}/dump.sql.gz"
  [[ -z "$DUMP_FILE" && -f "${SRC_DIR}/dump.sql" ]] && DUMP_FILE="${SRC_DIR}/dump.sql"

  if [[ -n "$DUMP_FILE" ]]; then
    b "==> Importando dump (${DUMP_FILE##*/})"
    if [[ "$DUMP_FILE" == *.gz ]]; then DEC="gzip -dc"; else DEC="cat"; fi
    set +e
    $DEC "$DUMP_FILE" | sed 's/DEFINER=`[^`]\+`@`[^`]\+` //g' \
      | docker exec -i mysql mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" "${DB_NAME}"
    RC=$?; set -e
    [[ $RC -eq 0 ]] || die "Falha ao importar o dump."
    DUMP_IMPORTED=1
    rm -f -- "${SRC_DIR}/dump.sql" "${SRC_DIR}/dump.sql.gz" || true
    ok "Dump importado e removido."
  else
    warn "Nenhum dump encontrado em ${SRC_DIR}."
  fi
fi

save_state
