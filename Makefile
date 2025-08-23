# Makefile — SetupForcoder
# Alvos principais:
#   make traefik:deploy   -> sobe Traefik no Swarm
#   make app:new          -> cria/deploya um novo app Laravel
#   make network:init     -> cria rede overlay 'edge' (se não existir)
#   make traefik:rm       -> remove stack do Traefik

include .env

EDGE ?= edge

.PHONY: traefik:deploy traefik:rm network:init app:new

network:init:
	@bash -c 'docker network ls --format "{{.Name}}" | grep -qx "$(EDGE)" || docker network create -d overlay --attachable $(EDGE) || true'
	@echo "OK: overlay network '$(EDGE)' pronta."

traefik:deploy: network:init
	@echo ">> Deploy do Traefik em Swarm…"
	@CF_API_TOKEN="$(CF_API_TOKEN)" \
	CF_ZONE_ID="$(CF_ZONE_ID)" \
	ACME_EMAIL="$(ACME_EMAIL)" \
	EDGE="$(EDGE)" \
	docker stack deploy -c stacks/traefik/compose.yml traefik
	@echo "OK: Traefik deployado (stack: traefik)."

traefik:rm
	@docker stack rm traefik || true
	@echo "OK: Traefik removido (pode levar alguns segundos)."

app:new: network:init
	@bash scripts/app_new.sh
