# shellcheck shell=bash
docker network inspect proxy >/dev/null 2>&1 || { docker network create proxy; ok "Rede docker 'proxy' criada."; }
docker network inspect db    >/dev/null 2>&1 || { docker network create db;    ok "Rede docker 'db' criada."; }
