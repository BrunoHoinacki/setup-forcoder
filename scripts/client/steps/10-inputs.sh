#!/usr/bin/env bash
set -euo pipefail

b "==> Novo projeto (wizard)"

read -rp "Cliente (ex.: cliente1): " CLIENT
read -rp "Projeto (ex.: site): " PROJECT
read -rp "Domínio (ex.: app.cliente.com.br): " DOMAIN
validate_domain_dns "$DOMAIN" || true

echo
b "Modo de deploy"
if is_swarm_active; then
  echo "  [1] Docker Compose (padrão)"
  echo "  [2] Docker Swarm (stack)"
  read -rp "Escolha [1/2] (1): " _m; _m="${_m:-1}"
  case "$_m" in
    2) MODE="swarm";;
    *) MODE="compose";;
  esac
else
  MODE="compose"
  warn "Swarm não está ativo neste nó; usando Compose."
fi
STACK_NAME="${PROJECT}"

echo
read -rp "Versão do PHP do container [8.2]: " PHP_VER
PHP_VER="${PHP_VER:-8.2}"
[[ "$PHP_VER" =~ ^8\.(1|2|3|4)$ ]] || die "Versão de PHP inválida."
if [[ "$PHP_VER" = "8.3" || "$PHP_VER" = "8.4" ]]; then
  warn "Alguns pacotes podem não suportar ${PHP_VER} (ex.: mpdf)."
fi

echo
echo "Banco de dados:"
echo "  [1] SQLite (padrão)"
echo "  [2] MySQL (central)"
read -rp "Escolha [1/2] (1): " DB_OPT; DB_OPT="${DB_OPT:-1}"
[[ "$DB_OPT" =~ ^[12]$ ]] || die "Escolha inválida."
DB_MODE="sqlite"; [[ "$DB_OPT" = "2" ]] && DB_MODE="mysql"

echo
echo "Origem do código:"
echo "  [1] Git (SSH)  [padrão]"
echo "  [2] ZIP local"
echo "  [3] Vazio (você sobe depois)"
read -rp "Escolha [1/2/3] (1): " CODE_SRC_OPT; CODE_SRC_OPT="${CODE_SRC_OPT:-1}"
[[ "$CODE_SRC_OPT" =~ ^[123]$ ]] || die "Escolha inválida."

GIT_SSH_URL=""; GIT_BRANCH="main"; ZIP_PATH=""
if [[ "$CODE_SRC_OPT" = "1" ]]; then
  read -rp "URL SSH do repo (ex.: git@github.com:org/repo.git): " GIT_SSH_URL
  [[ -n "$GIT_SSH_URL" ]] || die "Informe URL SSH."
  validate_git_ssh "$GIT_SSH_URL"
  read -rp "Branch [main]: " GIT_BRANCH; GIT_BRANCH="${GIT_BRANCH:-main}"
elif [[ "$CODE_SRC_OPT" = "2" ]]; then
  read -rp "ZIP absoluto (ex.: /opt/zips/projeto.zip): " ZIP_PATH
  [[ -f "$ZIP_PATH" ]] || die "ZIP não encontrado."
fi

NEED_VIEWSMYSQL=0
ask_yes_no "Rodar 'php artisan viewsmysql:make' após dump-autoload? [y/N]:" "N" && NEED_VIEWSMYSQL=1

echo
b "Dependências Composer"
echo "  [1] Produção (--no-dev)  [recomendado]"
echo "  [2] Desenvolvimento (com dev)"
read -rp "Escolha (1/2) [1]: " _opt_comp; _opt_comp="${_opt_comp:-1}"
COMPOSER_WITH_DEV=0; [[ "$_opt_comp" = "2" ]] && COMPOSER_WITH_DEV=1

echo
b "Execuções Laravel (se houver artisan)"
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

# Caminhos base
ROOT="/home/${CLIENT}/${PROJECT}"
NGX_DIR="${ROOT}/nginx"
SRC_DIR="${ROOT}/src"
COMPOSE="${ROOT}/docker-compose.yml"
STACK_FILE="${ROOT}/stack.yml"
PHP_SQLITE_DF="${ROOT}/php.sqlite.Dockerfile"
PHP_MYSQL_DF="${ROOT}/php.mysql.Dockerfile"
STATE="${ROOT}/.provision/state.env"

# Middleware Traefik herdado do setup
APP_CANONICAL_MW="www-to-root@docker"
if [[ -f /opt/traefik/.env ]]; then
  . /opt/traefik/.env || true
  [[ "${CANONICAL_MW:-www-to-root}" == "root-to-www" ]] && APP_CANONICAL_MW="root-to-www@docker"
fi

# Preview DB
DB_NAME_PREVIEW="(n/a - sqlite)"; DB_USER_PREVIEW="(n/a)"
if [[ "$DB_MODE" = "mysql" ]]; then
  DB_NAME_PREVIEW="$(echo "${CLIENT}_${PROJECT}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g' | cut -c1-64)"
  DB_USER_PREVIEW="$(echo "u_${CLIENT}_${PROJECT}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g' | cut -c1-32)"
fi

b "==> Resumo"
cat <<RES
Cliente        : ${CLIENT}
Projeto        : ${PROJECT}
Domínio        : ${DOMAIN}
Deploy (MODE)  : ${MODE}
PHP            : ${PHP_VER}
Origem código  : $( [[ "$CODE_SRC_OPT" = "1" ]] && echo "Git ${GIT_SSH_URL} (branch ${GIT_BRANCH})" || [[ "$CODE_SRC_OPT" = "2" ]] && echo "ZIP ${ZIP_PATH}" || echo "Vazio")
DB Mode        : ${DB_MODE}
DB_NAME        : ${DB_NAME_PREVIEW}
DB_USER        : ${DB_USER_PREVIEW}
Composer       : $( [[ ${COMPOSER_WITH_DEV:-0} -eq 1 ]] && echo "com dev" || echo "produção (--no-dev)" )
Migrate        : $( [[ ${RUN_MIGRATE:-0} -eq 1 ]] && echo "SIM" || echo "NÃO" )
Seed           : $( [[ ${RUN_SEED:-0} -eq 1 ]] && echo "SIM" || echo "NÃO" )
menu:make      : $( [[ ${RUN_MENU_MAKE:-0} -eq 1 ]] && echo "SIM" || echo "NÃO" )
PHP Profile    : $( [[ "${PHP_PROFILE}" = "auto" ]] && echo "auto (pelo composer.json)" || echo "${PHP_PROFILE}" )
RES

ask_yes_no "Prosseguir com a criação? [y/N]:" "N" || die "Abortado."

save_state
