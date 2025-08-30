# 🚀 Infraestrutura Multi-Cliente com Traefik + Docker

Este repositório monta uma **infraestrutura multi-cliente** em uma VPS usando **Docker** e **Traefik** como proxy reverso com **SSL automático (Let’s Encrypt)**.
Cada cliente tem seu **próprio domínio** e uma stack isolada (ex.: **Laravel + PHP-FPM + Nginx**). Opcionalmente, os projetos podem usar um **MySQL central** com **phpMyAdmin**.

```
DNS → VPS (80/443) → Traefik → Nginx do projeto → PHP-FPM do projeto → (opcional) MySQL central
```

> **Nota:** após o certificado ser emitido, o Traefik leva \~5s para começar a servir HTTPS.

---

## ⚡ Uso em 1 comando com `toolbox.sh` (recomendado)

O **toolbox** é um menu interativo que orquestra todos os scripts desta infra (setup inicial, provisionamento, remoções, utilitários e backups).

### Primeira execução (instalação da infra na VPS)

Como o repo é privado, envie-o para a VPS e rode o toolbox:

```bash
# na sua máquina
scp -r ./ root@SEU_IP:/opt/devops-stack/

# na VPS
ssh root@SEU_IP
cd /opt/devops-stack
bash scripts/toolbox.sh
```

No menu, escolha **“1) Setup inicial da VPS”** para subir o **Traefik** (com HTTPS), criar redes `proxy/db`, proteger o dashboard e, opcionalmente, instalar **MySQL + phpMyAdmin**.

### Principais opções do toolbox

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

## 📦 O que está pronto

### `scripts/setup.sh` — Setup inicial da VPS

Prepara a **infra base** em `/opt/traefik`, sobe o **Traefik** (HTTPS automático), cria as redes `proxy`/`db`, protege o **dashboard** e, opcionalmente, instala **MySQL + phpMyAdmin**.
📖 Detalhes: [docs/setup.md](docs/setup.md)

### `scripts/mkclient.sh` — Provisionamento de projetos

Cria a stack de um **cliente/projeto** em `/home/<cliente>/<projeto>`, integrada ao Traefik existente (Nginx + PHP-FPM; SQLite ou MySQL).
📖 Detalhes: [docs/mkclient.md](docs/mkclient.md)

### `scripts/delclient.sh` — Remover um projeto

Remove **um projeto** (derruba containers, apaga pasta e opcionalmente **DROP DATABASE/USER**).

### `scripts/delallclients.sh` — Remover TODOS os projetos

Remove **todos os projetos de todos os clientes** (mesma lógica do `delclient.sh`, porém em lote).

### `scripts/generaldocker.sh` — Utilitários Docker/Compose

Menu para `ps`, `up -d`, `down`, `restart`, `logs -f`, `rebuild`, `shell`, `artisan`, `optimize:clear`, **fix perms**, etc.

### `scripts/generalgit.sh` — Utilitários Git

Menu para `status`, `fetch`, `pull`, `log --oneline`, `branches`, `changed files`.

### `scripts/mkbackup.sh` — Backup de projetos

Gera `.zip` em `/opt/backups/<cliente>/<projeto>/` (código + `dump.sql.gz` ou `database.sqlite`).

### `scripts/resetsetup.sh` — Reset da infra base

Derruba Traefik/MySQL/PMA, remove `/opt/traefik` (inclui ACME) e redes `proxy/db` se vazias.

---

## ✅ Requisitos

* VPS Ubuntu/Debian com acesso root (ou `sudo`).
* DNS do **domínio do dashboard** apontando em **A/AAAA** para o IP da VPS.
* Repositório privado enviado via **SCP/rsync/SFTP**.
* (Opcional) Chave SSH no GitHub (para projetos privados usados pelo `mkclient.sh`).

---

## 🧱 Provisionar um novo cliente/projeto (via toolbox)

```bash
bash /opt/devops-stack/scripts/toolbox.sh
# opção 2: Provisionar cliente/projeto
```

> O `mkclient.sh` detecta Laravel e faz pós-instalação; integra labels/middlewares do Traefik automaticamente.

---

## 🔧 Operações do dia a dia (via toolbox)

* **Docker** (logs, restart, shell, artisan, fix perms): opção **5**
* **Git** (pull, log, status): opção **6**
* **Backup**: opção **7**
* **Recriar/Sobe Traefik**: opção **8**
* **Logs do Traefik**: opção **9**

---

## 🧰 Troubleshooting

* **SSL não emite (HTTP-01)** → DNS A/AAAA correto e **DNS cinza** até emitir.
* **SSL não emite (DNS-01)** → conferir **API Token** e permissões “DNS Edit”.
* **phpMyAdmin** → acesse com **barra final** `/phpmyadmin/`.
* **Portas 80/443 ocupadas** → `systemctl disable --now apache2 nginx`.
* **Ver logs do Traefik** → `docker logs -f traefik` e `tail -f /opt/traefik/logs/access.json`.

---

## 🔐 Segurança & Backups

Backups recomendados:

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

Após provisionar a **infra** ou um **novo projeto**, recomendamos executar um checklist rápido de segurança para validar portas abertas, regras de firewall, configuração de SSH e containers expostos.

📖 Veja o guia completo: [docs/security_verify.md](docs/security_verify.md)

---

## 🗺️ Roadmap

* Templates de queue/cron (Horizon/Supervisord)
* Rate limit & security headers padrão por serviço
* Backups automáticos
* Logs centralizados (Loki/Promtail + Grafana)
* Redis / Meilisearch opcionais

---

## ✅ Resumo

* **`toolbox.sh`** → **1 comando** para instalar, operar e manter a infra.
* `setup.sh` → sobe Traefik + SSL + MySQL opcional.
* `mkclient.sh` → provisiona projetos isolados.
* `delclient.sh` / `delallclients.sh` → removem projetos.
* `generaldocker.sh` / `generalgit.sh` → utilitários do dia a dia.
* `mkbackup.sh` → gera backups.
* `resetsetup.sh` → reseta a infra base.

---