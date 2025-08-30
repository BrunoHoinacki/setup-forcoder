docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
docker network inspect db    >/dev/null 2>&1 || docker network create db

if id -u "$CLIENT" >/dev/null 2>&1; then
  ok "Usuário '$CLIENT' já existe."
else
  b "==> Criando usuário '$CLIENT'"
  adduser --disabled-password --gecos "" "$CLIENT"
  passwd -d "$CLIENT" >/dev/null 2>&1 || true
  mkdir -p "/home/$CLIENT/.ssh"; touch "/home/$CLIENT/.ssh/authorized_keys"
  chmod 700 "/home/$CLIENT/.ssh"; chmod 600 "/home/$CLIENT/.ssh/authorized_keys"
  chown -R "$CLIENT:$CLIENT" "/home/$CLIENT"
fi

mkdir -p "${NGX_DIR}" "${SRC_DIR}" "${ROOT}/.composer-cache" "${ROOT}/.provision"
chown -R "${CLIENT}:${CLIENT}" "/home/${CLIENT}"

save_state
