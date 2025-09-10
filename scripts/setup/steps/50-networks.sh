# shellcheck shell=bash
b "==> Criando redes overlay (proxy, db)"

# overlay + attachable (permite containers standalone se precisar)
docker network ls --format '{{.Name}} {{.Driver}} {{.Scope}}' | grep -q '^proxy ' \
  || { docker network create --driver overlay --attachable proxy; ok "Rede 'proxy' criada (overlay)."; }

docker network ls --format '{{.Name}} {{.Driver}} {{.Scope}}' | grep -q '^db ' \
  || { docker network create --driver overlay --attachable db; ok "Rede 'db' criada (overlay)."; }
