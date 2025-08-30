#!/usr/bin/env bash
set -euo pipefail

# =============== generalgit.sh =====================
# Git helpers em /home/<cliente>/<projeto>/src
# - REQUIRE root
# - Ajusta safe.directory p/ root
# - status / fetch / pull / log -n N / branches / changed files
# ===================================================

b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo "  [OK] $*"; }
warn(){ echo "  [!] $*"; }
die(){ echo "  [ERR] $*" >&2; exit 1; }
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo su)."; }

need_root
read -rp "Cliente (ex.: cliente1): " CLIENT
read -rp "Projeto (ex.: site): " PROJECT

SRC="/home/${CLIENT}/${PROJECT}/src"
[ -d "$SRC" ] || die "Diretório não encontrado: $SRC"
cd "$SRC"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "Não é um repositório Git: $SRC"
fi

# evita erro 'detected dubious ownership' quando root opera em /home/<cliente>
git config --global --add safe.directory "$SRC" 2>/dev/null || true

cur_branch(){ git rev-parse --abbrev-ref HEAD; }
pick_branch(){
  b "Branches locais:"; git --no-pager branch -vv || true
  local cur; cur="$(cur_branch)"
  read -rp "Branch p/ PULL (ENTER=${cur}): " BR
  echo "${BR:-$cur}"
}

while true; do
  echo
  b "==> Git @ $SRC"
  cat <<'MENU'
  [1] Status (short)
  [2] Fetch (todas remotas)
  [3] Pull (branch atual ou escolhido)
  [4] Log --oneline (-n N)
  [5] Branches (locais/remotos)
  [6] Arquivos alterados (porcelain)
  [0] Sair
MENU
  read -rp "Opção: " OP
  case "${OP:-}" in
    1) b "[status]"; git --no-pager status -sb ;;
    2) b "[fetch]";  git fetch --all --prune; ok "Fetch OK."; ;;
    3)
       BR="$(pick_branch)"; b "Pull no branch: $BR"
       git checkout "$BR" >/dev/null 2>&1 || warn "Não troquei de branch (talvez já esteja em $BR)."
       git --no-pager pull --ff-only
       ;;
    4)
       read -rp "Quantos commits? (default 20): " N; N="${N:-20}"
       [[ "$N" =~ ^[0-9]+$ ]] || { warn "Número inválido, usando 20."; N=20; }
       git --no-pager log --oneline -n "$N" --decorate
       ;;
    5)
       echo "-- Locais --";  git --no-pager branch -vv || true
       echo; echo "-- Remotos --"; git --no-pager branch -r || true
       ;;
    6) b "[porcelain]"; git status --porcelain ;;
    0) exit 0 ;;
    *) warn "Opção desconhecida." ;;
  esac
done
