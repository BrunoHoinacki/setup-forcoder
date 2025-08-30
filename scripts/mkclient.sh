#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="${BASE_DIR}/client/steps"
LIB="${BASE_DIR}/client/lib.sh"

export START_AT="${START_AT:-}"   # ex: START_AT=50 ./mkclient.sh
export STOP_AT="${STOP_AT:-}"     # ex: STOP_AT=80 ./mkclient.sh

source "${LIB}"
need_root

# Se já existir STATE, carrega (permite retomar)
if [[ -n "${STATE:-}" && -f "${STATE}" ]]; then
  # shellcheck disable=SC1090
  source "${STATE}"
fi

for step in "${STEP_DIR}"/[0-9][0-9]-*.sh; do
  n="$(basename "$step" | cut -d- -f1)"
  if [[ -n "${START_AT}" && "$n" -lt "${START_AT}" ]]; then continue; fi
  if [[ -n "${STOP_AT}"  && "$n" -gt "${STOP_AT}"  ]]; then break;   fi
  b "==> Step ${n}: $(basename "$step")"
  # shellcheck disable=SC1090
  source "$step"
  ok "Step ${n} concluído."
done
