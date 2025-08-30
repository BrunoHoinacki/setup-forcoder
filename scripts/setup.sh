#!/usr/bin/env bash
set -euo pipefail

# driver fino que só carrega helpers e roda steps na ordem
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="${BASE_DIR}/setup"
STEPS_DIR="${SETUP_DIR}/steps"

# shellcheck source=setup/lib.sh
. "${SETUP_DIR}/lib.sh"

run_step() {
  local f="$1"
  # shellcheck source=/dev/null
  . "${STEPS_DIR}/${f}"
}

run_step 10-prereqs.sh
run_step 20-inputs.sh
run_step 30-install-docker.sh
run_step 40-ssh-github.sh
run_step 50-networks.sh
run_step 60-traefik-files.sh
run_step 70-compose.sh
run_step 80-up.sh
run_step 90-notes.sh
