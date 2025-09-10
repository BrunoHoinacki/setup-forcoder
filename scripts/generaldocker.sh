#!/usr/bin/env bash
set -euo pipefail

# =============== generaldocker.sh ==================
# Atalhos Docker/Compose/Swarm por projeto (CLIENTE/PROJETO)
# - REQUIRE root
# - Detecta automaticamente se o projeto usa Compose (docker-compose.yml)
#   ou Swarm (stack <projeto> com stack.yml)
# - NUNCA roda composer install/update
# - Em Swarm: usa docker service/logs/update/exec em tarefas
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
STACK_FILE="${ROOT}/stack.yml"
STACK_NAME="${PROJECT}"

[ -d "$ROOT" ] || die "Diretório do projeto não existe: $ROOT"

is_swarm_active(){ docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q '^active$'; }
stack_exists(){ docker stack ls --format '{{.Name}}' | grep -qx "$STACK_NAME"; }

MODE="compose"
if is_swarm_active && stack_exists; then
  MODE="swarm"
elif is_swarm_active && [ -f "$STACK_FILE" ]; then
  MODE="swarm"
elif [ -f "$COMPOSE" ]; then
  MODE="compose"
fi

b "Resumo"
echo " - Cliente : $CLIENT"
echo " - Projeto : $PROJECT"
echo " - Path    : $ROOT"
echo " - Modo    : $MODE"
echo

cd "$ROOT"

# ===== Helpers COMPOSE =====
compose_services(){
  docker compose config --services 2>/dev/null || docker compose ps --services 2>/dev/null || true
}

# ===== Helpers SWARM =====
# Lista serviços da stack
swarm_services(){
  docker service ls --format '{{.Name}}' | awk -F_ -v s="${STACK_NAME}_" '$1==s{print $0}' 2>/dev/null
}

# Escolhe um serviço da stack (default php/nginx se houver)
pick_swarm_service(){
  local def="$1"
  mapfile -t SVC < <(swarm_services)
  ((${#SVC[@]}==0)) && { echo ""; return 1; }
  local i=1
  echo "Serviços da stack:"
  for s in "${SVC[@]}"; do echo " $i) $s"; ((i++)); done
  read -rp "Escolha [1-${#SVC[@]}] (ENTER=${def}): " CH
  [[ -z "$CH" && -n "$def" ]] && { echo "$def"; return; }
  [[ "$CH" =~ ^[0-9]+$ ]] && ((CH>=1 && CH<=${#SVC[@]})) && { echo "${SVC[CH-1]}"; return; }
  [[ -n "$def" ]] && echo "$def" || echo ""
}

# Pega um container (task) rodando daquele serviço
task_container_for_service(){
  local svc="$1"
  # pega ID de uma task RUNNING
  local tid
  tid="$(docker service ps --filter 'desired-state=running' --format '{{.ID}}' "$svc" | head -n1 || true)"
  [ -z "$tid" ] && return 1
  # task->container ID
  docker inspect --format '{{.Status.ContainerStatus.ContainerID}}' "$tid" 2>/dev/null || true
}

default_swarm_service(){
  # tenta <stack>_php, depois <stack>_nginx, senão o primeiro
  if docker service ls --format '{{.Name}}' | grep -qx "${STACK_NAME}_php"; then
    echo "${STACK_NAME}_php"; return
  fi
  if docker service ls --format '{{.Name}}' | grep -qx "${STACK_NAME}_nginx"; then
    echo "${STACK_NAME}_nginx"; return
  fi
  swarm_services | head -n1
}

while true; do
  echo
  b "==> Ações ($MODE)"
  if [ "$MODE" = "compose" ]; then
    [ -f "$COMPOSE" ] || die "docker-compose.yml não encontrado: $COMPOSE"
    mapfile -t SERVICES < <(compose_services | awk 'NF' | sort)
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
        # pick service
        def="nginx"; [[ " ${SERVICES[*]} " == *" php "* ]] && def="php"
        echo "Serviços:"; i=1; for s in "${SERVICES[@]}"; do echo " $i) $s"; ((i++)); done
        read -rp "Escolha serviço (ENTER=${def}): " svc; svc="${svc:-$def}"
        b "Restart: $svc"; docker compose restart "$svc"
        ;;
      5)
        def="php"; [[ " ${SERVICES[*]} " != *" php "* ]] && def="${SERVICES[0]:-}"
        read -rp "Serviço (ENTER=${def}): " svc; svc="${svc:-$def}"
        read -rp "Seguir (-f)? [y/N]: " F
        if [[ "${F^^}" == "Y" ]]; then docker compose logs -f "$svc"
        else read -rp "Tail (default 200): " T; T="${T:-200}"; docker compose logs --tail="$T" "$svc"
        fi
        ;;
      6)
        def="php"; [[ " ${SERVICES[*]} " != *" php "* ]] && def="${SERVICES[0]:-}"
        read -rp "Serviço para rebuild (ENTER=${def}): " svc; svc="${svc:-$def}"
        echo "ATENÇÃO: recompila **apenas a imagem** de '$svc'."
        read -rp "Confirmar rebuild de '$svc'? [y/N]: " C
        [[ "${C^^}" == "Y" ]] || { warn "Cancelado."; continue; }
        docker compose build "$svc" && docker compose up -d; ok "Rebuild concluído."
        ;;
      7)
        def="php"; [[ " ${SERVICES[*]} " != *" php "* ]] && def="${SERVICES[0]:-}"
        read -rp "Serviço (ENTER=${def}): " svc; svc="${svc:-$def}"
        docker compose exec -it "$svc" bash || docker compose exec -it "$svc" sh
        ;;
      8)
        svc="php"; [[ " ${SERVICES[*]} " != *" php "* ]] && { echo "Serviço 'php' não existe."; continue; }
        read -rp "artisan comando (default: about): " ART; ART="${ART:-about}"
        docker compose exec -it "$svc" php artisan $ART
        ;;
      9)
        svc="php"; [[ " ${SERVICES[*]} " != *" php "* ]] && { echo "Serviço 'php' não existe."; continue; }
        b "Limpando caches no '$svc'..."
        docker compose exec -it "$svc" php artisan optimize:clear || true
        docker compose exec -it "$svc" php artisan config:clear   || true
        docker compose exec -it "$svc" php artisan route:clear    || true
        docker compose exec -it "$svc" php artisan view:clear     || true
        ok "Caches limpos."
        ;;
      10) printf '%s\n' "${SERVICES[@]}" ;;
      11)
        svc="php"; [[ " ${SERVICES[*]} " != *" php "* ]] && { echo "Serviço 'php' não existe."; continue; }
        b "Corrigindo permissões em 'storage' e 'bootstrap/cache'..."
        docker compose exec -it "$svc" sh -lc '
          set -e
          chown -R www-data:www-data storage bootstrap/cache || true
          find storage bootstrap/cache -type d -exec chmod 775 {} \; || true
          find storage bootstrap/cache -type f -exec chmod 664 {} \; || true
          rm -f storage/framework/views/*.php || true
          php artisan optimize:clear || true
        '
        ok "Permissões corrigidas e caches limpos."
        ;;
      0) exit 0 ;;
      *) warn "Opção desconhecida." ;;
    esac
  else
    # ===== SWARM =====
    cat <<'MENU'
  [1] Status (docker service ls / ps)
  [2] Deploy/Update stack (docker stack deploy -c stack.yml <nome>)
  [3] Remover stack (docker stack rm <nome>)
  [4] Forçar restart de um serviço (docker service update --force)
  [5] Logs de serviço (docker service logs)
  [6] Shell em uma task de serviço (docker exec)
  [7] Artisan em 'php' (service task)
  [8] Corrigir permissões (storage/bootstrap/cache) em 'php'
  [0] Sair
MENU
    read -rp "Opção: " OP
    case "${OP:-}" in
      1)
        b "[service ls]"
        docker service ls --format 'table {{.Name}}\t{{.Mode}}\t{{.Replicas}}\t{{.Ports}}'
        echo
        b "[service ps ${STACK_NAME}_*]"
        docker service ps "${STACK_NAME}_*" --no-trunc --format 'table {{.Name}}\t{{.CurrentState}}\t{{.Node}}'
        ;;
      2)
        [ -f "$STACK_FILE" ] || die "stack.yml não encontrado: $STACK_FILE"
        b "[stack deploy]"; docker stack deploy -c "$STACK_FILE" "$STACK_NAME"; ok "Deploy/Update enviado."
        ;;
      3)
        b "[stack rm]"; docker stack rm "$STACK_NAME" || true
        ;;
      4)
        def="$(default_swarm_service)"
        read -rp "Serviço para --force (ENTER=${def}): " svc; svc="${svc:-$def}"
        [ -n "$svc" ] || { warn "Sem serviço."; continue; }
        docker service update --force "$svc"; ok "Update forçado enviado."
        ;;
      5)
        def="$(default_swarm_service)"
        read -rp "Serviço (ENTER=${def}): " svc; svc="${svc:-$def}"
        [ -n "$svc" ] || { warn "Sem serviço."; continue; }
        read -rp "Seguir (-f)? [y/N]: " F
        if [[ "${F^^}" == "Y" ]]; then docker service logs -f "$svc"
        else read -rp "Tail (default 200): " T; T="${T:-200}"; docker service logs --tail "$T" "$svc"
        fi
        ;;
      6)
        def="$(default_swarm_service)"
        read -rp "Serviço (ENTER=${def}): " svc; svc="${svc:-$def}"
        [ -n "$svc" ] || { warn "Sem serviço."; continue; }
        cid="$(task_container_for_service "$svc" || true)"
        [ -n "$cid" ] || { warn "Nenhuma task RUNNING encontrada para $svc."; continue; }
        docker exec -it "$cid" bash || docker exec -it "$cid" sh
        ;;
      7)
        svc="${STACK_NAME}_php"
        if ! docker service ls --format '{{.Name}}' | grep -qx "$svc"; then
          warn "Serviço $svc não encontrado."; continue
        fi
        cid="$(task_container_for_service "$svc" || true)"
        [ -n "$cid" ] || { warn "Nenhuma task RUNNING encontrada para $svc."; continue; }
        read -rp "artisan comando (default: about): " ART; ART="${ART:-about}"
        docker exec -it "$cid" php artisan $ART
        ;;
      8)
        svc="${STACK_NAME}_php"
        if ! docker service ls --format '{{.Name}}' | grep -qx "$svc"; then
          warn "Serviço $svc não encontrado."; continue
        fi
        cid="$(task_container_for_service "$svc" || true)"
        [ -n "$cid" ] || { warn "Nenhuma task RUNNING encontrada para $svc."; continue; }
        b "Corrigindo permissões em 'storage' e 'bootstrap/cache'..."
        docker exec -it "$cid" sh -lc '
          set -e
          chown -R www-data:www-data storage bootstrap/cache || true
          find storage bootstrap/cache -type d -exec chmod 775 {} \; || true
          find storage bootstrap/cache -type f -exec chmod 664 {} \; || true
          rm -f storage/framework/views/*.php || true
          php artisan optimize:clear || true
        '
        ok "Permissões corrigidas e caches limpos."
        ;;
      0) exit 0 ;;
      *) warn "Opção desconhecida." ;;
    esac
  fi
done
