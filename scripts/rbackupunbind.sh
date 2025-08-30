#!/usr/bin/env bash
set -euo pipefail

# ============== rbackupunbind.sh ====================
# Desfaz bind mounts de /opt/rbackup/<cliente>/<projeto>/src
# Pergunta se é para 1 projeto ou para todos.
# Aceita: rbackupunbind.sh <cliente> <projeto>
# ====================================================

b(){ echo -e "\033[1m$*\033[0m"; }
ok(){ echo "  [OK] $*"; }
warn(){ echo "  [!] $*"; }
err(){ echo "  [ERR] $*" >&2; }
die(){ err "$*"; exit 1; }
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "Execute como root (sudo)."; }

TARGET_GLOB='^/opt/rbackup/[^/]+/[^/]+/src$'

is_mounted(){
  local tgt="$1"
  if command -v mountpoint >/dev/null 2>&1; then
    mountpoint -q "$tgt"
  else
    findmnt -n --target "$tgt" >/dev/null 2>&1
  fi
}

unbind_one(){
  local client="$1" project="$2"
  local tgt="/opt/rbackup/${client}/${project}/src"
  if is_mounted "$tgt"; then
    umount "$tgt" 2>/dev/null || umount -l "$tgt"
    ok "Desmontado: $tgt"
  else
    warn "Não estava montado: $tgt"
  fi
  rmdir -p "$tgt" 2>/dev/null || true
}

unbind_all(){
  local any=0
  while IFS= read -r m; do
    any=1
    umount "$m" 2>/dev/null || umount -l "$m"
    ok "Desmontado: $m"
    rmdir -p "$m" 2>/dev/null || true
  done < <(findmnt -rn -o TARGET | grep -E "$TARGET_GLOB" || true)
  [ "$any" -eq 0 ] && warn "Nenhum bind encontrado em /opt/rbackup/*/*/src"
}

main(){
  need_root
  if [ $# -eq 2 ]; then unbind_one "$1" "$2"; exit 0; fi
  b "==> Desfazer binds de /opt/rbackup/<cliente>/<projeto>/src"
  echo "1) Desfazer bind de UM projeto"
  echo "2) Desfazer bind de TODOS os projetos"
  read -rp "Selecione: " opt
  case "$opt" in
    1) read -rp "Cliente: " c; [ -n "${c:-}" ] || die "Cliente vazio.";
       read -rp "Projeto: " p; [ -n "${p:-}" ] || die "Projeto vazio.";
       unbind_one "$c" "$p" ;;
    2) unbind_all ;;
    *) die "Opção inválida." ;;
  esac
  ok "Concluído."
}
main "$@"
