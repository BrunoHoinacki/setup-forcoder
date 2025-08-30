#!/usr/bin/env bash
set -e

# ========= UI =========
echo -e "\033[1;36m==> Instalando SetupForcoder...\033[0m"

# ========= Verifica root =========
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[1;31m[ERRO] Execute como root\033[0m"
    exit 1
fi

# ========= Config =========
ROOT="/opt/setup-forcoder"
URL="https://github.com/BrunoHoinacki/setup-forcoder/archive/refs/heads/main.tar.gz"

# ========= Instala dependências básicas =========
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
chmod +x "$ROOT"/scripts/*.sh

# ========= Atalho =========
ln -sf "$ROOT/scripts/toolbox.sh" /usr/local/bin/setupforcoder

echo -e "\033[1;32m✓ SetupForcoder instalado!\033[0m"
echo
echo -e "\033[1;33mPara usar, digite: setupforcoder\033[0m"
