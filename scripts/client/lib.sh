#!/usr/bin/env bash
set -euo pipefail

# -------- UI --------
b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo "  [OK] $*"; }
warn(){ echo "  [!] $*"; }
die(){ echo "  [ERR] $*" >&2; exit 1; }
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo su)."; }
esc_sed(){ printf '%s' "$1" | sed -e 's/[\/&#]/\\&/g'; }

ask_yes_no(){
  local prompt="$1" default="${2:-N}" ans
  read -rp "$prompt " ans || true
  ans="${ans:-$default}"; ans="$(tr '[:upper:]' '[:lower:]' <<<"$ans")"
  [[ "$ans" =~ ^(y|yes|s|sim)$ ]]
}

# -------- util --------
ensure_github_known_hosts(){
  mkdir -p /root/.ssh && chmod 700 /root/.ssh
  touch /root/.ssh/known_hosts && chmod 644 /root/.ssh/known_hosts
  ssh-keyscan -t ed25519,ecdsa,rsa github.com >> /root/.ssh/known_hosts 2>/dev/null || true

  su - "$CLIENT" -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/known_hosts && chmod 644 ~/.ssh/known_hosts'
  ssh-keyscan -t ed25519,ecdsa,rsa github.com >> "/home/$CLIENT/.ssh/known_hosts" 2>/dev/null || true
  chown "$CLIENT:$CLIENT" "/home/$CLIENT/.ssh/known_hosts"
}

ensure_unzip(){
  command -v unzip >/dev/null 2>&1 && return 0
  warn "Instalando 'unzip'..."
  if command -v apt-get >/dev/null; then apt-get update -y && apt-get install -y unzip >/dev/null
  elif command -v apk >/dev/null; then apk add --no-cache unzip >/dev/null
  elif command -v yum >/dev/null; then yum install -y unzip >/dev/null
  else die "Não consegui instalar 'unzip'."
  fi
  ok "unzip instalado."
}

upsert_env(){
  local file="$1" key="$2" val="$3" esc_val; esc_val="$(esc_sed "$val")"
  if grep -qE "^[[:space:]]*${key}=" "$file" 2>/dev/null; then
    sed -i -E "s|^[[:space:]]*${key}=.*|${key}=${esc_val}|g" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

adjust_env_existing(){
  local env_file="$1" db_mode="$2"
  upsert_env "$env_file" "APP_ENV" "production"
  upsert_env "$env_file" "APP_DEBUG" "false"
  upsert_env "$env_file" "APP_URL" "https://${DOMAIN}"
  upsert_env "$env_file" "SESSION_SECURE_COOKIE" "true"
  upsert_env "$env_file" "TRUSTED_PROXIES" "*"
  upsert_env "$env_file" "TRUSTED_HEADERS" "X_FORWARDED_ALL"
  if [[ "$db_mode" = "mysql" ]]; then
    upsert_env "$env_file" "DB_CONNECTION" "mysql"
    upsert_env "$env_file" "DB_HOST" "mysql"
    upsert_env "$env_file" "DB_PORT" "3306"
    upsert_env "$env_file" "DB_DATABASE" "${DB_NAME}"
    upsert_env "$env_file" "DB_USERNAME" "${DB_USER}"
    upsert_env "$env_file" "DB_PASSWORD" "${DB_PASS}"
  else
    upsert_env "$env_file" "DB_CONNECTION" "sqlite"
    upsert_env "$env_file" "DB_DATABASE" "/var/www/html/database/database.sqlite"
    sed -i -E '/^[[:space:]]*DB_HOST=/d;/^[[:space:]]*DB_PORT=/d;/^[[:space:]]*DB_USERNAME=/d;/^[[:space:]]*DB_PASSWORD=/d' "$env_file"
  fi
}

# -------- validações UX --------
validate_domain_dns(){
  local dom="$1"
  command -v getent >/dev/null 2>&1 || { warn "getent ausente; pulando validação DNS."; return 0; }
  local ip_me ip_dns
  ip_me="$(curl -fsSL ifconfig.me || curl -fsSL icanhazip.com || echo '')"
  ip_dns="$(getent ahostsv4 "$dom" 2>/dev/null | awk '/STREAM/ {print $1; exit}')"
  if [[ -z "$ip_me" || -z "$ip_dns" ]]; then
    warn "Não consegui validar DNS → VPS. Continue, mas certifique o A/AAAA do domínio."
    return 0
  fi
  if [[ "$ip_me" != "$ip_dns" ]]; then
    warn "DNS de $dom resolve para $ip_dns, mas o IP desta VPS é $ip_me."
    warn "Para HTTP-01, deixe o DNS 'cinza' apontando para $ip_me até emitir o certificado."
    return 0
  fi
  ok "DNS do domínio aponta para esta VPS ($ip_me)."
}

validate_git_ssh(){
  local url="$1"
  ensure_github_known_hosts
  ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | grep -qi "successfully authenticated" || \
    warn "SSH com GitHub ainda não autenticado. Se der erro no git clone, rode o setup (40-ssh-github) e tente de novo."
  [[ "$url" =~ ^git@github\.com:.+\.git$ ]] || warn "URL não parece SSH do GitHub (git@github.com:org/repo.git)."
}

# -------- ACME trigger --------
trigger_acme_and_wait(){
  local domain="$1" acme="/opt/traefik/letsencrypt/acme.json" t=0 timeout=120
  curl -kIs "https://${domain}" >/dev/null 2>&1 || true
  while [ $t -lt $timeout ]; do
    if [ -f "$acme" ] && grep -q "\"main\"\\s*:\\s*\"${domain}\"" "$acme" && grep -q "\"certificate\"" "$acme"; then
      ok "Certificado emitido para ${domain}."; return 0
    fi
    local line
    line="$(docker logs --since 60s traefik 2>/dev/null | grep -F "$domain" | tail -n1 || true)"
    if echo "$line" | grep -qi 'Unable to obtain ACME certificate'; then
      echo "$line" | sed 's/^/  [ACME] /'; return 1
    fi
    sleep 3; t=$((t+3))
  done
  warn "Não vi o cert de ${domain} em ${timeout}s. Veja logs do traefik."
  return 1
}

# -------- Compose/Swarm runners unificados --------
is_swarm_active(){ docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q '^active$'; }
task_container_for_service(){
  local svc="$1"
  local tid cid
  tid="$(docker service ps --filter 'desired-state=running' --format '{{.ID}}' "$svc" | head -n1 || true)"
  [ -z "$tid" ] && return 1
  cid="$(docker inspect --format '{{.Status.ContainerStatus.ContainerID}}' "$tid" 2>/dev/null || true)"
  [ -n "$cid" ] && echo "$cid"
}

run_in_php(){
  # Usa MODE (compose|swarm), ROOT, STACK_NAME (== PROJECT), executa comando no container php
  local cmd="$*"
  if [[ "${MODE}" = "compose" ]]; then
    ( cd "${ROOT}" && docker compose run --rm php bash -lc "$cmd" )
  else
    local svc="${STACK_NAME}_php"
    local cid; cid="$(task_container_for_service "$svc" || true)"
    [ -n "$cid" ] || die "Nenhuma task RUNNING do serviço $svc."
    docker exec -it "$cid" bash -lc "$cmd" || docker exec -it "$cid" sh -lc "$cmd"
  fi
}

# -------- STATE --------
save_state(){
  mkdir -p "$(dirname "$STATE")"
  {
    printf 'CLIENT=%q\n' "$CLIENT"
    printf 'PROJECT=%q\n' "$PROJECT"
    printf 'STACK_NAME=%q\n' "${STACK_NAME:-$PROJECT}"
    printf 'DOMAIN=%q\n' "$DOMAIN"
    printf 'MODE=%q\n' "$MODE"
    printf 'PHP_VER=%q\n' "$PHP_VER"
    printf 'DB_MODE=%q\n' "$DB_MODE"
    printf 'CODE_SRC_OPT=%q\n' "$CODE_SRC_OPT"
    printf 'GIT_SSH_URL=%q\n' "${GIT_SSH_URL:-}"
    printf 'GIT_BRANCH=%q\n' "${GIT_BRANCH:-}"
    printf 'ZIP_PATH=%q\n' "${ZIP_PATH:-}"
    printf 'NEED_VIEWSMYSQL=%q\n' "${NEED_VIEWSMYSQL:-0}"
    printf 'COMPOSER_WITH_DEV=%q\n' "${COMPOSER_WITH_DEV:-0}"
    printf 'RUN_MIGRATE=%q\n' "${RUN_MIGRATE:-0}"
    printf 'RUN_SEED=%q\n' "${RUN_SEED:-0}"
    printf 'RUN_MENU_MAKE=%q\n' "${RUN_MENU_MAKE:-0}"
    printf 'ROOT=%q\n' "$ROOT"
    printf 'SRC_DIR=%q\n' "$SRC_DIR"
    printf 'NGX_DIR=%q\n' "$NGX_DIR"
    printf 'COMPOSE=%q\n' "$COMPOSE"
    printf 'STACK_FILE=%q\n' "$STACK_FILE"
    printf 'PHP_SQLITE_DF=%q\n' "$PHP_SQLITE_DF"
    printf 'PHP_MYSQL_DF=%q\n' "$PHP_MYSQL_DF"
    printf 'DB_NAME=%q\n' "${DB_NAME:-}"
    printf 'DB_USER=%q\n' "${DB_USER:-}"
    printf 'DB_PASS=%q\n' "${DB_PASS:-}"
    printf 'DUMP_IMPORTED=%q\n' "${DUMP_IMPORTED:-0}"
    printf 'APP_CANONICAL_MW=%q\n' "${APP_CANONICAL_MW:-www-to-root@docker}"
  } > "$STATE"
}

# Carrega STATE se existir quando um step roda “sozinho”
if [[ -n "${STATE:-}" && -f "${STATE}" ]]; then
  # shellcheck disable=SC1090
  source "${STATE}"
fi
