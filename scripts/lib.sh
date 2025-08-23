#!/usr/bin/env bash
set -Eeuo pipefail

exists_network() {
  local net="$1"
  docker network ls --format '{{.Name}}' | grep -qx "$net"
}

ensure_overlay() {
  local net="$1"
  if ! exists_network "$net"; then
    docker network create -d overlay --attachable "$net" >/dev/null
  fi
}

prompt() {
  local var="$1" msg="$2" def="${3:-}"
  local val
  read -rp "$msg ${def:+[$def]}: " val || true
  echo "${val:-$def}"
}
