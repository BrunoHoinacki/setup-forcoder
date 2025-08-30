if [[ "$CODE_SRC_OPT" = "1" ]]; then
  b "==> Clonando ${GIT_SSH_URL} (branch ${GIT_BRANCH}) em ${SRC_DIR}"
  ensure_github_known_hosts
  if GIT_SSH_COMMAND="ssh -i /root/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
     git clone -b "${GIT_BRANCH}" --depth 1 "${GIT_SSH_URL}" "${SRC_DIR}"; then
    ok "Clonado com a chave do root."
  else
    warn "Falha com root. Tentando com o usuário ${CLIENT}..."
    su - "$CLIENT" -c "GIT_SSH_COMMAND='ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new' git clone -b ${GIT_BRANCH} --depth 1 ${GIT_SSH_URL} ${SRC_DIR}" \
      || die "Falha ao clonar repo."
  fi
  chown -R "${CLIENT}:${CLIENT}" "${SRC_DIR}"
elif [[ "$CODE_SRC_OPT" = "2" ]]; then
  ensure_unzip
  tmpdir="$(mktemp -d)"; unzip -q "$ZIP_PATH" -d "$tmpdir"
  shopt -s dotglob; entries=( "$tmpdir"/* )
  if (( ${#entries[@]} == 1 )) && [[ -d "${entries[0]}" ]]; then
    mv "${entries[0]}"/* "$SRC_DIR"/
  else
    mv "$tmpdir"/* "$SRC_DIR"/
  fi
  shopt -u dotglob; rm -rf "$tmpdir"
  chown -R "${CLIENT}:${CLIENT}" "${SRC_DIR}"
else
  warn "Sem origem de código — 'src/' ficará vazio."
fi

save_state
