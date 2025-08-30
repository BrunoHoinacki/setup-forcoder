#!/usr/bin/env bash
set -euo pipefail

# =============== generaldocker.sh ==================
# Atalhos Docker/Compose por projeto (CLIENTE/PROJETO)
# - REQUIRE root
# - NUNCA roda composer install/update
# - Rebuild de imagem apenas com confirmação explícita
# - ps / up -d / down / restart / logs / shell / artisan / optimize:clear
# ===================================================

b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo "  [OK] $*"; }
warn(){ echo "  [!] $*"; }
die(){ echo "  [ERR] $*" >&2; exit 1; }
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo su)."; }

need_root
read -rp "Cliente (ex.: cliente1): " CLIENT
read -rp "Projeto (ex.: site): " PROJECT

ROOT="/home/${CLIENT}/${PROJECT}"
COMPOSE="${ROOT}/docker-compose.yml"

[ -d "$ROOT" ] || die "Diretório do projeto não existe: $ROOT"
[ -f "$COMPOSE" ] || die "docker-compose.yml não encontrado: $COMPOSE"

b "Resumo"
echo " - Cliente : $CLIENT"
echo " - Projeto : $PROJECT"
echo " - Path    : $ROOT"
echo " - Compose : $COMPOSE"
echo

cd "$ROOT"

get_services() {
  local s
  if s=$(docker compose config --services 2>/dev/null); then
    echo "$s"
  else
    docker compose ps --services 2>/dev/null || true
  fi
}
mapfile -t SERVICES < <(get_services | awk 'NF' | sort)

print_svcs(){
  ((${#SERVICES[@]}==0)) && { echo " (nenhum serviço detectado)" >&2; return; }
  {
    echo "Serviços:"
    local i=1
    for s in "${SERVICES[@]}"; do
      echo " $i) $s"
      ((i++))
    done
  } >&2
}

default_svc(){
  for s in "${SERVICES[@]}"; do [[ "$s" == "php" ]] && { echo php; return; }; done
  ((${#SERVICES[@]}>0)) && echo "${SERVICES[0]}" || echo ""
}

pick_svc(){
  local def="${1:-$(default_svc)}"
  print_svcs
  local max=${#SERVICES[@]}
  ((max==0)) && { echo ""; return 1; }
  read -rp "Escolha [1-${max}] (ENTER=${def}): " CH
  [[ -z "$CH" && -n "$def" ]] && { echo "$def"; return; }
  [[ "$CH" =~ ^[0-9]+$ ]] && ((CH>=1 && CH<=max)) && { echo "${SERVICES[CH-1]}"; return; }
  warn "Opção inválida."; return 1
}

while true; do
  echo
  b "==> Ações"
  cat <<'MENU'
  [1] Status (ps)
  [2] Subir (up -d)
  [3] Derrubar (down)
  [4] Reiniciar serviço (restart)
  [5] Logs (seguir opcional)
  [6] Rebuild IMAGEM do serviço (confirmar)    [default: php]
  [7] Shell no serviço (bash/sh)               [default: php]
  [8] Artisan (comando livre)                  [no 'php']
  [9] Limpar caches Laravel (optimize:clear, etc.)
  [10] Listar serviços do projeto
  [11] Corrigir permissões (storage/bootstrap/cache)
  [0] Sair
MENU
  read -rp "Opção: " OP
  case "${OP:-}" in
    1) b "[ps]"; docker compose ps ;;
    2) b "[up -d]"; docker compose up -d; ok "Stack online." ;;
    3) b "[down]"; docker compose down; ok "Stack parada." ;;
    4)
      svc="$(pick_svc nginx || true)"; [[ -n "${svc:-}" ]] || continue
      b "Restart: $svc"; docker compose restart "$svc"
      ;;
    5)
      svc="$(pick_svc "$(default_svc)" || true)"; [[ -n "${svc:-}" ]] || continue
      read -rp "Seguir (-f)? [y/N]: " F
      if [[ "${F^^}" == "Y" ]]; then
        docker compose logs -f "$svc"
      else
        read -rp "Tail (default 200): " T; T="${T:-200}"
        docker compose logs --tail="$T" "$svc"
      fi
      ;;
    6)
      svc="$(pick_svc php || true)"; [[ -n "${svc:-}" ]] || continue
      echo "ATENÇÃO: isso recompila **apenas a imagem** de '$svc'."
      echo "Não roda composer install/update; não mexe no vendor montado."
      read -rp "Confirmar rebuild de '$svc'? [y/N]: " C
      [[ "${C^^}" == "Y" ]] || { warn "Cancelado."; continue; }
      docker compose build "$svc"
      docker compose up -d
      ok "Rebuild concluído."
      ;;
    7)
      svc="$(pick_svc php || true)"; [[ -n "${svc:-}" ]] || continue
      docker compose exec -it "$svc" bash || docker compose exec -it "$svc" sh
      ;;
    8)
      if printf '%s\n' "${SERVICES[@]}" | grep -qx php; then
        svc=php
      else
        svc="$(pick_svc || true)"
      fi
      [[ -n "${svc:-}" ]] || continue
      read -rp "artisan comando (default: about): " ART; ART="${ART:-about}"
      docker compose exec -it "$svc" php artisan $ART
      ;;
    9)
      if printf '%s\n' "${SERVICES[@]}" | grep -qx php; then
        svc=php
      else
        svc="$(pick_svc || true)"
      fi
      [[ -n "${svc:-}" ]] || continue
      b "Limpando caches no '$svc'..."
      docker compose exec -it "$svc" php artisan optimize:clear || true
      docker compose exec -it "$svc" php artisan config:clear   || true
      docker compose exec -it "$svc" php artisan route:clear    || true
      docker compose exec -it "$svc" php artisan view:clear     || true
      ok "Caches limpos."
      ;;
    10) print_svcs ;;
    11)
      if printf '%s\n' "${SERVICES[@]}" | grep -qx php; then
        svc=php
      else
        svc="$(pick_svc || true)"
      fi
      [[ -n "${svc:-}" ]] || continue
      b "Corrigindo permissões em 'storage' e 'bootstrap/cache' no '$svc'..."
      docker compose exec -it "$svc" sh -lc '
        set -e
        echo "[1/4] Ajustando ownership..."
        chown -R www-data:www-data storage bootstrap/cache || true
        echo "[2/4] Ajustando permissões de diretórios..."
        find storage bootstrap/cache -type d -exec chmod 775 {} \; || true
        echo "[3/4] Ajustando permissões de arquivos..."
        find storage bootstrap/cache -type f -exec chmod 664 {} \; || true
        echo "[4/4] Limpando views e caches..."
        rm -f storage/framework/views/*.php || true
        php artisan optimize:clear || true
      '
      ok "Permissões corrigidas e caches limpos."
      ;;
    0) exit 0 ;;
    *) warn "Opção desconhecida." ;;
  esac
done
