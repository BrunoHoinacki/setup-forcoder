#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="${BASE_DIR}/client/steps"
LIB="${BASE_DIR}/client/lib.sh"

# Permite retomar do meio: START_AT=50 STOP_AT=80 ./mkclient.sh
export START_AT="${START_AT:-}"
export STOP_AT="${STOP_AT:-}"

source "${LIB}"
need_root

# Se existir STATE (retomada), carrega
if [[ -n "${STATE:-}" && -f "${STATE}" ]]; then
  # shellcheck disable=SC1090
  source "${STATE}"
fi

# Listagem amigável quando passar só START_AT/STOP_AT errado
ls_steps(){ ls -1 "${STEP_DIR}"/[0-9][0-9]-*.sh | xargs -n1 -I{} basename "{}"; }

for step in "${STEP_DIR}"/[0-9][0-9]-*.sh; do
  n="$(basename "$step" | cut -d- -f1)"
  if [[ -n "${START_AT}" && "$n" -lt "${START_AT}" ]]; then continue; fi
  if [[ -n "${STOP_AT}"  && "$n" -gt "${STOP_AT}"  ]]; then break;   fi
  b "==> Step ${n}: $(basename "$step")"
  # shellcheck disable=SC1090
  source "$step"
  ok "Step ${n} concluído."
done
