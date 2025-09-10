#!/usr/bin/env bash
set -e

# ========= UI =========
clear
printf "\033[1;36m"
cat <<'BANNER'
███████╗ ██████╗ ██████╗  ██████╗ ██████╗ ██████╗ ███████╗██████╗ 
██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗
█████╗  ██║   ██║██████╔╝██║     ██║   ██║██║  ██║█████╗  ██████╔╝
██╔══╝  ██║   ██║██╔══██╗██║     ██║   ██║██║  ██║██╔══╝  ██╔══██╗
██║     ╚██████╔╝██║  ██║╚██████╗╚██████╔╝██████╔╝███████╗██║  ██║
╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
BANNER
printf "\033[0m\n"
echo -e "\033[1;36m==> Instalando SetupForcoder...\033[0m"

# ========= Verifica root =========
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[1;31m[ERRO] Execute como root\033[0m"
  exit 1
fi

# ========= Config =========
ROOT="/opt/setup-forcoder"
URL="https://github.com/BrunoHoinacki/setup-forcoder/archive/refs/heads/main.tar.gz"

# ========= LOGS =========
LOG_DIR="/var/log/setup-forcoder-logs"
mkdir -p "$LOG_DIR"
chmod 0755 "$LOG_DIR" || true
LOG_FILE="${LOG_DIR}/install-$(date +%F_%H%M%S).log"

# duplica stdout/stderr para tela e arquivo (linha a linha)
exec > >(stdbuf -oL -eL tee -a "$LOG_FILE") 2>&1
echo "---- BEGIN INSTALL $(date -Iseconds) on $(hostname) ----"
echo "Log: $LOG_FILE"

# cria/atualiza logrotate
cat >/etc/logrotate.d/setup-forcoder <<'ROT'
/var/log/setup-forcoder-logs/*.log {
    rotate 8
    weekly
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
ROT

# ========= Instala dependências básicas =========
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y curl tar unzip ca-certificates

# ========= Download e extração =========
rm -rf "$ROOT"
mkdir -p "$ROOT"

echo "Baixando arquivos..."
curl -sL "$URL" | tar -xz -C /tmp/

# Move arquivos
mv /tmp/setup-forcoder-main/* "$ROOT/"
rm -rf /tmp/setup-forcoder-main

# ========= Permissões =========
find "$ROOT" -name "*.sh" -type f -exec chmod +x {} \;

# ========= Atalho CORRETO =========
cat > /usr/local/bin/setupforcoder << 'EOF'
#!/bin/bash
exec bash /opt/setup-forcoder/scripts/toolbox.sh "$@"
EOF
chmod +x /usr/local/bin/setupforcoder

echo -e "\033[1;32m✓ SetupForcoder instalado com sucesso!\033[0m"
echo
echo -e "\033[1;33mPara usar, execute qualquer um dos comandos:\033[0m"
echo -e "\033[1;32m  setupforcoder\033[0m"
echo -e "\033[1;32m  bash /opt/setup-forcoder/scripts/toolbox.sh\033[0m"
echo
echo "Log desta instalação: $LOG_FILE"

# ========= Executa automaticamente se possível =========
if [ -t 0 ] && [ -t 1 ]; then
  echo -e "\033[1;36mIniciando toolbox automaticamente...\033[0m"
  sleep 1
  exec bash "$ROOT/scripts/toolbox.sh"
else
  echo -e "\033[1;33mExecute um dos comandos acima para abrir o toolbox.\033[0m"
fi
