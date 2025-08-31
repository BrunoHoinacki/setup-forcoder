# 🚀 SetupForcoder — Infraestrutura Multi-Cliente com Traefik + Docker

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Este repositório monta uma **infraestrutura multi-cliente** em uma VPS usando **Docker** e **Traefik** como proxy reverso com **SSL automático (Let’s Encrypt)**.
Cada cliente tem seu **próprio domínio** e uma stack isolada (ex.: **Laravel + PHP-FPM + Nginx**). Opcionalmente, os projetos podem usar um **MySQL central** com **phpMyAdmin**.

```
DNS → VPS (80/443) → Traefik → Nginx do projeto → PHP-FPM do projeto → (opcional) MySQL central
```

> **Nota:** após o certificado ser emitido, o Traefik leva \~5s para começar a servir HTTPS.

---

## ⚡ Instalação em 1 comando

Na sua VPS Ubuntu/Debian (como **root**):

```bash
curl -fsSL https://raw.githubusercontent.com/BrunoHoinacki/setup-forcoder/main/scripts/install.sh | sudo bash
```

Isso irá baixar o **toolbox** e iniciar o menu interativo para provisionar toda a infra.

No menu, escolha **“1) Setup inicial da VPS”** para subir o **Traefik** (com HTTPS), criar redes `proxy/db`, proteger o dashboard e, opcionalmente, instalar **MySQL + phpMyAdmin**.

---

## ⚙️ Principais opções do toolbox

1. **Setup inicial da VPS** (Traefik + redes + opcional MySQL/PMA)
2. **Provisionar cliente/projeto** (`mkclient.sh`)
3. **Remover projeto** (`delclient.sh`)
4. **Remover TODOS os projetos** (`delallclients.sh`)
5. **Utilitários Docker** do projeto (`generaldocker.sh`)
6. **Utilitários Git** do projeto (`generalgit.sh`)
7. **Backup** do projeto (`mkbackup.sh`)
8. **Recriar/sobe Traefik** (`docker compose up -d` em `/opt/traefik`)
9. **Logs do Traefik** (`tail -f /opt/traefik/logs/access.json`)

> Se preferir, todos esses scripts podem ser executados diretamente sem o toolbox.

---

## 🔶 Cloudflare (opcional)

O setup suporta **Cloudflare**:

* **Com API Token** → usa **DNS-01** (pode manter **proxy laranja** ligado).
* **Sem token (HTTP-01)** → deixe o DNS **cinza (DNS only)** até emitir o certificado.

Como criar o token: **[docs/token\_cloudflare.md](docs/token_cloudflare.md)**

---

## 📦 Scripts inclusos

* `scripts/setup.sh` — Setup inicial da VPS
* `scripts/mkclient.sh` — Provisionamento de projetos
* `scripts/delclient.sh` — Remove um projeto
* `scripts/delallclients.sh` — Remove todos os projetos
* `scripts/generaldocker.sh` — Utilitários Docker/Compose
* `scripts/generalgit.sh` — Utilitários Git
* `scripts/mkbackup.sh` — Backup de projetos
* `scripts/resetsetup.sh` — Reset da infra base

---

## ✅ Requisitos

* VPS Ubuntu/Debian com acesso root (ou `sudo`).
* DNS do **domínio do dashboard** apontando em **A/AAAA** para o IP da VPS.
* (Opcional) Chave SSH no GitHub (para projetos privados usados pelo `mkclient.sh`).

---

## 🧱 Provisionar um novo cliente/projeto

```bash
bash /opt/setupforcoder/scripts/toolbox.sh
# opção 2: Provisionar cliente/projeto
```

O `mkclient.sh` detecta Laravel e faz pós-instalação; integra labels/middlewares do Traefik automaticamente.

---

## 🔧 Operações do dia a dia (via toolbox)

* **Docker** (logs, restart, shell, artisan, fix perms) → opção 5
* **Git** (pull, log, status) → opção 6
* **Backup** → opção 7
* **Recriar/Sobe Traefik** → opção 8
* **Logs do Traefik** → opção 9

---

## 🔐 Segurança & Backups

Recomenda-se backup de:

* `/opt/traefik/letsencrypt/acme.json` (certificados)
* `/home/<cliente>/<projeto>/` (código + assets)
* `/opt/traefik/mysql-data` (MySQL)
* `/src/database/database.sqlite` (SQLite)

Boas práticas:

* Rotacionar credenciais do BasicAuth do dashboard
* Ativar e ajustar firewall (UFW)
* Manter imagens/pacotes atualizados

---

## 🛡️ Checklist de Verificação (pós-instalação)

Após provisionar a infra ou um novo projeto, execute um checklist rápido de segurança para validar portas abertas, regras de firewall, configuração de SSH e containers expostos.

📖 Veja o guia completo: [docs/security\_verify.md](docs/security_verify.md)

---

## 🗺️ Roadmap

* Templates de queue/cron (Horizon/Supervisord)
* Rate limit & security headers padrão por serviço
* Backups automáticos
* Logs centralizados (Loki/Promtail + Grafana)
* Redis / Meilisearch opcionais

---

## 📜 Licença

Distribuído sob a **MIT License**.
Veja o arquivo [`LICENSE.txt`](LICENSE.txt).

---
