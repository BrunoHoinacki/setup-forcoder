#!/usr/bin/env bash
set -euo pipefail

# ===========================
# resetsetup.sh  (versão Swarm)
# Zera a infra criada pelo setup.sh (Traefik + opcional MySQL/phpMyAdmin) em Docker Swarm
# - Remove a stack 'traefik' (Swarm)
# - (Opcional) preserva dados do MySQL em /opt/zips/*.tgz
# - Remove /opt/traefik (inclui ACME/certs/config)
# - Tenta remover redes overlay proxy/db se vazias
# - (Opcional) leave do Swarm
# Mantém compatibilidade com legado (compose) se existir docker-compose.yml
# ===========================

b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo -e "  [OK] $*"; }
warn(){ echo -e "  [!] $*"; }
die(){ echo -e "  [ERR] $*" >&2; exit 1; }

need_root() { [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo su)."; }

ask_yes_no() {
  local prompt="$1" default="${2:-N}" ans
  read -rp "$prompt " ans || true
  ans="${ans:-$default}"
  ans="$(echo "$ans" | tr '[:upper:]' '[:lower:]')"
  [[ "$ans" = "y" || "$ans" = "yes" || "$ans" = "s" || "$ans" = "sim" ]]
}

have_container() { docker ps -a --format '{{.Names}}' | grep -qx "$1"; }
rm_container() { have_container "$1" && { docker rm -f "$1" >/dev/null && ok "Container '$1' removido."; } || true; }

net_is_empty() {
  local n
  n="$(docker network inspect "$1" --format '{{len .Containers}}' 2>/dev/null || echo "ERR")"
  [[ "$n" = "0" ]]
}

stack_exists() { docker stack ls --format '{{.Name}}' | grep -qx "$1"; }

wait_stack_removed() {
  local name="$1" tries=30
  while [ $tries -gt 0 ]; do
    if ! stack_exists "$name"; then return 0; fi
    sleep 1; tries=$((tries-1))
  done
  return 1
}

TRAEFIK_DIR="/opt/traefik"
MYSQL_DATA_DIR="${TRAEFIK_DIR}/mysql-data"

need_root
command -v docker >/dev/null 2>&1 || die "Docker não encontrado. Nada para resetar."

b "==> Reset da infra (Swarm) — Traefik / MySQL / phpMyAdmin"
echo "Isto vai remover a stack 'traefik', (opcionalmente) MySQL/phpMyAdmin e apagar ${TRAEFIK_DIR}."
read -rp "Para confirmar, digite DELETE: " CONFIRM
[[ "$CONFIRM" == "DELETE" ]] || die "Abortado."

# 0) Legacy: derrubar via compose se existir (compatibilidade)
if [ -f "${TRAEFIK_DIR}/docker-compose.yml" ]; then
  b "==> [LEGADO] docker compose down (com volumes/orphans) em ${TRAEFIK_DIR}"
  ( cd "${TRAEFIK_DIR}" && docker compose down --volumes --remove-orphans ) || warn "compose down retornou erro (seguindo)."
fi

# 1) Remover a stack Swarm 'traefik' (se existir)
if stack_exists "traefik"; then
  b "==> Removendo stack 'traefik' (Swarm)"
  docker stack rm traefik || warn "Falha ao remover stack (seguindo)."
  b "==> Aguardando serviços finalizarem…"
  if ! wait_stack_removed "traefik"; then
    warn "A stack 'traefik' ainda aparece listada. Continuando mesmo assim."
  else
    ok "Stack 'traefik' removida."
  fi
else
  warn "Stack 'traefik' não encontrada (talvez já removida)."
fi

# 2) Remover containers por nome (se sobrar algo de modo legado)
rm_container traefik
rm_container phpmyadmin
rm_container mysql

# 3) Opcional: preservar dados do MySQL (bind mount em /opt/traefik/mysql-data)
PRESERVED_ARCHIVE=""
if [ -d "${MYSQL_DATA_DIR}" ]; then
  if ask_yes_no "Deseja PRESERVAR os dados do MySQL (compactar em /opt/zips)? [y/N]:" "N"; then
    mkdir -p /opt/zips
    TS="$(date +%Y%m%d-%H%M%S)"
    PRESERVED_ARCHIVE="/opt/zips/mysql-data-${TS}.tgz"
    b "==> Compactando dados do MySQL (${MYSQL_DATA_DIR}) em ${PRESERVED_ARCHIVE}"
    tar -czf "${PRESERVED_ARCHIVE}" -C "${TRAEFIK_DIR}" "mysql-data"
    ok "Backup salvo em: ${PRESERVED_ARCHIVE}"
  else
    warn "Você optou por NÃO preservar os dados do MySQL."
  fi
fi

# 4) Apagar /opt/traefik inteiro (ACME/certs/config, logs, dynamic, etc.)
if [ -d "${TRAEFIK_DIR}" ]; then
  b "==> Removendo ${TRAEFIK_DIR}"
  rm -rf --one-file-system "${TRAEFIK_DIR}"
  ok "Diretório removido."
else
  warn "${TRAEFIK_DIR} não existe — nada a remover."
fi

# 5) Tentar remover redes overlay proxy/db (somente se vazias)
for NET in proxy db; do
  if docker network inspect "$NET" >/dev/null 2>&1; then
    if net_is_empty "$NET"; then
      if docker network rm "$NET" >/dev/null 2>&1; then
        ok "Rede '${NET}' removida."
      else
        warn "Não foi possível remover a rede '${NET}'."
      fi
    else
      warn "Rede '${NET}' ainda tem containers conectados — mantendo."
    fi
  fi
done

# 6) (Opcional) sair do Swarm
if ask_yes_no "Deseja também sair do Docker Swarm neste nó (docker swarm leave --force)? [y/N]: " "N"; then
  docker swarm leave --force || warn "Falha ao sair do Swarm."
  ok "Saiu do Swarm neste nó."
fi

# 7) Dicas finais
b "==> Limpeza concluída!"
[ -n "${PRESERVED_ARCHIVE}" ] && echo "Backup MySQL preservado: ${PRESERVED_ARCHIVE}"
echo "Para reconfigurar, rode novamente o setup:"
echo "  bash /opt/devops-stack/scripts/setup.sh"
echo
echo "Se for mudar o domínio do dashboard Traefik, informe o novo domínio quando o setup pedir."
