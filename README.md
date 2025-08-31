# 🚀 SetupForcoder — Infraestrutura Multi-Cliente com Traefik + Docker

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-orange?logo=ubuntu)
![Debian](https://img.shields.io/badge/Debian-10%2B-red?logo=debian)
![Docker](https://img.shields.io/badge/Docker-Compose-blue?logo=docker)
![Laravel](https://img.shields.io/badge/Laravel-10.x-ff2d20?logo=laravel)
![Traefik](https://img.shields.io/badge/Traefik-2.11-blue?logo=traefikproxy)
![Cloudflare](https://img.shields.io/badge/Cloudflare-DNS%20%2B%20SSL-f38020?logo=cloudflare)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](https://github.com/BrunoHoinacki/setup-forcoder/pulls)

---

Este repositório monta uma **infraestrutura multi-cliente** em uma VPS usando **Docker** e **Traefik** como proxy reverso com **SSL automático (Let’s Encrypt)**.
Cada cliente tem seu **próprio domínio** e uma stack isolada (ex.: **Laravel + PHP-FPM + Nginx**).
Opcionalmente, os projetos podem usar um **MySQL central** com **phpMyAdmin**.

```
DNS → VPS (80/443) → Traefik → Nginx do projeto → PHP-FPM do projeto → (opcional) MySQL central
```

📖 Veja um [exemplo em funcionamento (SQLite)](docs/exemplo_sqlite.md).

---

## 🌍 Compatibilidade & Filosofia

O **SetupForcoder** foi pensado para atender tanto **projetos legados** quanto **arquiteturas modernas**:

* **Legado (LAMP-like)** → Projetos ainda em `/home/<cliente>/<projeto>/src`, com dumps SQL diretos e assets em `/storage/public/`.
* **Moderno (Laravel em containers)** → Provisionamento via Docker Compose, stack isolada, Nginx + PHP-FPM, MySQL central opcional, Traefik com SSL automático.

Essa compatibilidade garante que empresas em transição possam adotar o SetupForcoder sem quebrar fluxos já existentes.

---

## ⚡ Instalação em 1 comando

Na sua VPS Ubuntu/Debian (como **root**):

```bash
curl -fsSL https://raw.githubusercontent.com/BrunoHoinacki/setup-forcoder/main/scripts/install.sh | sudo bash
```

Isso irá baixar o **toolbox** e iniciar o menu interativo para provisionar toda a infra.

📖 Guia detalhado: [docs/setup.md](docs/setup.md)

---

## ⚙️ Principais opções do toolbox

1. **Setup inicial da VPS** (Traefik + redes + opcional MySQL/PMA)
2. **Provisionar cliente/projeto** ([docs/mkclient.md](docs/mkclient.md))
3. **Remover projeto** (`delclient.sh`)
4. **Remover TODOS os projetos** (`delallclients.sh`)
5. **Utilitários Docker** do projeto (`generaldocker.sh`)
6. **Utilitários Git** do projeto
7. **Backup** do projeto (`mkbackup.sh`)
8. **Recriar/sobe Traefik** (`docker compose up -d` em `/opt/traefik`)
9. **Logs do Traefik** (`tail -f /opt/traefik/logs/access.json`)

---

## 🔶 Cloudflare (opcional)

O setup suporta **Cloudflare**:

* **Com API Token** → usa **DNS-01** (pode manter **proxy laranja** ligado).
* **Sem token (HTTP-01)** → deixe o DNS **cinza (DNS only)** até emitir o certificado.

📖 Como criar o token: [docs/token\_cloudflare.md](docs/token_cloudflare.md)

---

## 🛡️ Checklist de Segurança

Após provisionar a infra ou um novo projeto, valide rede, SSH e containers expostos.

📖 Guia completo: [docs/security\_verify.md](docs/security_verify.md)

---

## 📦 Scripts inclusos

* `scripts/setup.sh` — Setup inicial da VPS ([docs/setup.md](docs/setup.md))
* `scripts/mkclient.sh` — Provisionamento de projetos ([docs/mkclient.md](docs/mkclient.md))
* `scripts/delclient.sh` — Remove um projeto
* `scripts/delallclients.sh` — Remove todos os projetos
* `scripts/generaldocker.sh` — Utilitários Docker/Compose
* `scripts/generalgit.sh` — Utilitários Git 
* `scripts/mkbackup.sh` — Backup de projetos (ZIP + dump SQL)
* `scripts/mkrbackup.sh` — Mantém dumps disponíveis para `rsync` incremental
* `scripts/resetsetup.sh` — Reset da infra base

---

## 🗺️ Roadmap

* [ ] Templates de queue/cron (Horizon/Supervisord)
* [ ] Rate limit & security headers padrão por serviço
* [ ] Backups automáticos (`auto_backup.sh` + `setup-cron-backups.sh`)
* [ ] **Script complementar de rsync** → para rodar em máquina local/servidor externo, sincronizando apenas alterações a partir de `/opt/rbackup`.
* [ ] Logs centralizados (Loki/Promtail + Grafana)
* [ ] Redis / Meilisearch opcionais

---

## 📖 Documentação complementar

* [Exemplo em funcionamento (SQLite)](docs/exemplo_sqlite.md)
* [Setup inicial da VPS](docs/setup.md)
* [Provisionamento de projetos (mkclient)](docs/mkclient.md)
* [Token Cloudflare](docs/token_cloudflare.md)
* [Checklist de segurança](docs/security_verify.md)
* [Vincular GitHub via SSH](docs/vincular_git.md)

---

## 📜 Licença

Distribuído sob a **MIT License**.
Veja o arquivo [`LICENSE.txt`](LICENSE.txt).

---
