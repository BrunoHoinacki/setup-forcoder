#!/usr/bin/env bash
set -euo pipefail

# Este step coleta todos os inputs necessários, mostra um resumo
# e persiste o state para os próximos steps.

# Requer que o orquestrador (mkclient.sh) já tenha carregado lib.sh
# (b, warn, die, ask_yes_no, esc_sed, save_state etc.)

# === Inputs (iguais ao original) =========================================
read -rp "Cliente (ex.: cliente1): " CLIENT
read -rp "Projeto (ex.: site): " PROJECT
read -rp "Domínio (ex.: app.cliente.com.br): " DOMAIN

read -rp "Versão do PHP do container [8.2]: " PHP_VER
PHP_VER="${PHP_VER:-8.2}"
# aceitar 8.1, 8.2, 8.3 e 8.4
[[ "$PHP_VER" =~ ^8\.(1|2|3|4)$ ]] || die "Versão de PHP inválida."
# avisar para as mais novas (compatibilidade de libs)
if [[ "$PHP_VER" = "8.3" || "$PHP_VER" = "8.4" ]]; then
  warn "Pacotes podem não suportar ${PHP_VER} (ex.: mpdf)."
fi

echo "Banco de dados:"
echo "  [1] SQLite (padrão)"
echo "  [2] MySQL (central)"
read -rp "Escolha [1/2] (1): " DB_OPT; DB_OPT="${DB_OPT:-1}"
[[ "$DB_OPT" =~ ^[12]$ ]] || die "Escolha inválida."
DB_MODE="sqlite"; [[ "$DB_OPT" = "2" ]] && DB_MODE="mysql"

echo "Origem do código:"
echo "  [1] Git (SSH)"
echo "  [2] ZIP local"
echo "  [3] Vazio"
read -rp "Escolha [1/2/3] (1): " CODE_SRC_OPT; CODE_SRC_OPT="${CODE_SRC_OPT:-1}"
[[ "$CODE_SRC_OPT" =~ ^[123]$ ]] || die "Escolha inválida."

GIT_SSH_URL=""; GIT_BRANCH="main"; ZIP_PATH=""
if [[ "$CODE_SRC_OPT" = "1" ]]; then
  read -rp "URL SSH do repo: " GIT_SSH_URL; [[ -n "$GIT_SSH_URL" ]] || die "Informe URL SSH."
  read -rp "Branch [main]: " GIT_BRANCH; GIT_BRANCH="${GIT_BRANCH:-main}"
elif [[ "$CODE_SRC_OPT" = "2" ]]; then
  read -rp "ZIP absoluto (ex.: /opt/zips/projeto.zip): " ZIP_PATH
  [[ -f "$ZIP_PATH" ]] || die "ZIP não encontrado."
fi

NEED_VIEWSMYSQL=0
ask_yes_no "Rodar 'php artisan viewsmysql:make' após dump-autoload? [y/N]:" "N" && NEED_VIEWSMYSQL=1

# === Novos inputs =========================================================
echo
b "Dependências Composer"
echo "  [1] Produção (composer install --no-dev)  [recomendado]"
echo "  [2] Desenvolvimento (composer install com dev)"
read -rp "Escolha (1/2) [1]: " _opt_comp
_opt_comp="${_opt_comp:-1}"
if [[ "$_opt_comp" = "2" ]]; then
  COMPOSER_WITH_DEV=1
else
  COMPOSER_WITH_DEV=0
fi

echo
b "Execuções opcionais do Laravel (se houver artisan)"
ask_yes_no "Rodar migrations (php artisan migrate --force)? [Y/n]:" "Y" && RUN_MIGRATE=1 || RUN_MIGRATE=0
ask_yes_no "Rodar seeders (php artisan db:seed --force)? [y/N]:" "N" && RUN_SEED=1 || RUN_SEED=0
ask_yes_no "Rodar menu:make (php artisan menu:make)? [y/N]:" "N" && RUN_MENU_MAKE=1 || RUN_MENU_MAKE=0

echo
b "Perfil PHP"
ask_yes_no "Detectar automaticamente pelo composer.json? [Y/n]:" "Y" && AUTO_PHP_PROFILE=1 || AUTO_PHP_PROFILE=0
PHP_PROFILE="auto"
if [[ "${AUTO_PHP_PROFILE}" -eq 0 ]]; then
  echo "  [1] Mínimo (pdo_mysql/sqlite, mbstring, bcmath, gd, zip, exif)"
  echo "  [2] Completo (Mínimo + intl)  [recomendado p/ Filament]"
  read -rp "Escolha (1/2) [2]: " _php_prof; _php_prof="${_php_prof:-2}"
  case "$_php_prof" in
    1) PHP_PROFILE="min";;
    2) PHP_PROFILE="full";;
    *) die "Escolha inválida.";;
  esac
fi
export AUTO_PHP_PROFILE PHP_PROFILE

DOMAIN_ESCAPED="$(esc_sed "$DOMAIN")"

# Cálculo de preview DB (somente para resumo)
DB_NAME_PREVIEW="(n/a - sqlite)"; DB_USER_PREVIEW="(n/a)"
if [[ "$DB_MODE" = "mysql" ]]; then
  DB_NAME_PREVIEW="$(echo "${CLIENT}_${PROJECT}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g' | cut -c1-64)"
  DB_USER_PREVIEW="$(echo "u_${CLIENT}_${PROJECT}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g' | cut -c1-32)"
fi

ROOT="/home/${CLIENT}/${PROJECT}"
NGX_DIR="${ROOT}/nginx"
SRC_DIR="${ROOT}/src"
COMPOSE="${ROOT}/docker-compose.yml"
PHP_SQLITE_DF="${ROOT}/php.sqlite.Dockerfile"
PHP_MYSQL_DF="${ROOT}/php.mysql.Dockerfile"
STATE="${ROOT}/.provision/state.env"

# Middleware Traefik
APP_CANONICAL_MW="www-to-root@docker"
if [[ -f /opt/traefik/.env ]]; then
  . /opt/traefik/.env || true
  [[ "${CANONICAL_MW:-www-to-root}" == "root-to-www" ]] && APP_CANONICAL_MW="root-to-www@docker"
fi

b "==> Resumo do provisionamento"
cat <<RES
Cliente        : ${CLIENT}
Projeto        : ${PROJECT}
Domínio        : ${DOMAIN}
PHP            : ${PHP_VER}
Origem código  : $( [[ "$CODE_SRC_OPT" = "1" ]] && echo "Git ${GIT_SSH_URL} (branch ${GIT_BRANCH})" || [[ "$CODE_SRC_OPT" = "2" ]] && echo "ZIP ${ZIP_PATH}" || echo "Vazio")
DB Mode        : ${DB_MODE}
DB_NAME        : ${DB_NAME_PREVIEW}
DB_USER        : ${DB_USER_PREVIEW}
Rodar views... : $( [[ $NEED_VIEWSMYSQL -eq 1 ]] && echo "SIM" || echo "NÃO" )
Composer       : $( [[ ${COMPOSER_WITH_DEV:-0} -eq 1 ]] && echo "com dev" || echo "produção (--no-dev)" )
Migrate        : $( [[ ${RUN_MIGRATE:-0} -eq 1 ]] && echo "SIM" || echo "NÃO" )
Seed           : $( [[ ${RUN_SEED:-0} -eq 1 ]] && echo "SIM" || echo "NÃO" )
menu:make      : $( [[ ${RUN_MENU_MAKE:-0} -eq 1 ]] && echo "SIM" || echo "NÃO" )
PHP Profile    : $( [[ "${PHP_PROFILE}" = "auto" ]] && echo "auto (detectado pelo composer.json)" || echo "${PHP_PROFILE}" )
RES

ask_yes_no "Prosseguir com a criação? [y/N]:" "N" || die "Abortado."

# Persiste o state
save_state
