# 🚀 SetupForcoder — Infraestrutura Multi-Cliente com Traefik + Docker Swarm

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%2B-orange?logo=ubuntu)
![Debian](https://img.shields.io/badge/Debian-10%2B-red?logo=debian)
![Docker](https://img.shields.io/badge/Docker-Swarm-blue?logo=docker)
![Laravel](https://img.shields.io/badge/Laravel-10.x-ff2d20?logo=laravel)
![Traefik](https://img.shields.io/badge/Traefik-2.11-blue?logo=traefikproxy)
![Cloudflare](https://img.shields.io/badge/Cloudflare-DNS%20%2B%20SSL-f38020?logo=cloudflare)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](https://github.com/BrunoHoinacki/setup-forcoder/pulls)

---

Este repositório monta uma **infraestrutura multi-cliente** em uma VPS usando **Docker Swarm** e **Traefik** como proxy reverso com **SSL automático (Let’s Encrypt)**.
Cada cliente tem seu **próprio domínio** e uma stack isolada (ex.: **Laravel + PHP-FPM + Nginx**).
Opcionalmente, os projetos podem usar um **MySQL central** com **phpMyAdmin**.

```
DNS → VPS (80/443) → Traefik (Swarm) → Nginx do projeto → PHP-FPM do projeto → (opcional) MySQL central
```

📖 Veja um [exemplo em funcionamento (SQLite)](docs/exemplo_sqlite.md).

---

## 🌍 Compatibilidade & Filosofia

O **SetupForcoder** foi pensado para atender tanto **projetos legados** quanto **arquiteturas modernas**:

* **Legado (LAMP-like)** → Projetos ainda em `/home/<cliente>/<projeto>/src`, com dumps SQL diretos e assets em `/storage/public/`.
* **Moderno (Laravel em containers)** → Provisionamento via **stack Swarm** (infra) + **Compose por projeto**, Nginx + PHP-FPM, MySQL central opcional, Traefik com SSL automático.

Essa compatibilidade garante que empresas em transição possam adotar o SetupForcoder sem quebrar fluxos já existentes.

> **Integração Swarm + Compose:**
>
> * A **infra** (Traefik + opcional MariaDB/phpMyAdmin) roda como **stack Swarm**.
> * Cada **projeto** sobe com **Docker Compose** próprio (isolado).
> * A ponte entre ambos são as **redes Docker externas**:
>
>   * `proxy` → expõe HTTP/HTTPS via Traefik
>   * `db` → acesso ao MySQL central (quando habilitado)

---

## ⚡ Instalação em 1 comando

Na sua VPS Ubuntu/Debian (como **root**):

```bash
curl -fsSL https://raw.githubusercontent.com/BrunoHoinacki/setup-forcoder/main/scripts/install.sh | sudo bash
```

Isso irá baixar o **toolbox** e iniciar o menu interativo para provisionar toda a infra.

📖 Guia detalhado: [docs/setup.md](docs/setup.md)

---

## 🧭 Como funciona (alto nível)

* **`scripts/setup.sh`** prepara a VPS:

  * Instala Docker/Compose, **inicializa Swarm**, cria redes externas `proxy` e `db`;
  * Provisiona **Traefik** como **stack Swarm** (HTTP/3, redirect global HTTP→HTTPS, dashboard com **BasicAuth**, middlewares `canonical + compress + secure-headers`, access log JSON);
  * Opcionalmente sobe **MariaDB (MySQL central)** + **phpMyAdmin** (em subpath `/phpmyadmin/`), ambos integrados ao Traefik e à rede `db`;
  * Suporte a **ACME HTTP-01** ou **DNS-01 (Cloudflare API Token)**.
* **`scripts/mkclient.sh`** (provisionador de projetos, **refatorado em steps**):

  * Inputs (cliente/projeto/domínio), **PHP 8.1/8.2/8.3/8.4**, origem do código (**Git via SSH**, **ZIP** ou **vazio**);
  * **Perfil PHP Automático**: detecta dependências no `composer.json` e escolhe **min** (essencial) ou **full** (com `intl`); pode ser forçado manualmente;
  * Banco: **SQLite** ou **MySQL central** (cria schema/usuário e importa `dump.sql(.gz)` se existir);
  * Gera `nginx.conf`, Dockerfiles **a partir de templates**, `.env` de produção e `docker-compose.yml` com labels Traefik e redes externas;
  * Sobe a stack do projeto (`docker compose up -d`), dispara emissão de certificado, e aplica ajustes Laravel (composer, key, optimize, migrate/seed, permissões).

---

## ▶️ Fluxo rápido

1. **Setup da infra (Swarm + Traefik + redes + opcional MySQL/phpMyAdmin)**

```bash
bash /opt/setup-forcoder/scripts/setup.sh
```

2. **Provisionar um projeto**

```bash
bash /opt/setup-forcoder/scripts/mkclient.sh
```

3. **Acompanhar**

```bash
docker service logs -f traefik_traefik
docker compose -f /home/<cliente>/<projeto>/docker-compose.yml logs -f nginx
```

---

## ⚙️ Principais opções do toolbox

1. **Setup inicial da VPS** (init do Swarm + Traefik stack + redes overlay + opcional MySQL/PMA)
2. **Provisionar cliente/projeto** ([docs/mkclient.md](docs/mkclient.md))
3. **Remover projeto** (`delclient.sh`)
4. **Remover TODOS os projetos** (`delallclients.sh`)
5. **Utilitários Docker** (status, prune, compose/stack helpers)
6. **Utilitários Git** (chaves, configs globais)
7. **Backup** do projeto (`mkbackup.sh`)
8. **Recriar/sobe Traefik** (`docker stack deploy -c /opt/traefik/stack.yml traefik`)
9. **Logs do Traefik** (`docker service logs -f traefik_traefik`)
10. **Reset da infra base** (`resetsetup.sh` – remove stack traefik, redes overlay, e opcionalmente sai do Swarm)

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

Dicas rápidas:

* Proteja o **dashboard** com BasicAuth (já habilitado) e, se necessário, **restrinja por IP**.
* Monitore **logs** (Traefik + app).
* Mantenha imagens e sistema atualizados.
* Faça backup de:

  * `/opt/traefik/letsencrypt/acme.json` (certificados)
  * `/opt/traefik/mysql-data` (se usar MySQL)

---

## 📦 Scripts inclusos

* `scripts/setup.sh` — Setup inicial da VPS em **Swarm** ([docs/setup.md](docs/setup.md))
* `scripts/mkclient.sh` — Provisionamento de projetos ([docs/mkclient.md](docs/mkclient.md))
* `scripts/delclient.sh` — Remove um projeto
* `scripts/delallclients.sh` — Remove todos os projetos
* `scripts/generaldocker.sh` — Utilitários Docker (Compose + Swarm)
* `scripts/generalgit.sh` — Utilitários Git
* `scripts/mkbackup.sh` — Backup de projetos (ZIP + dump SQL)
* `scripts/mkrbackup.sh` — Mantém dumps disponíveis para `rsync` incremental
* `scripts/resetsetup.sh` — Reset da infra base (remove stack traefik, redes overlay, e opcionalmente sai do Swarm)

---

## 📚 Convenções & Integração de Redes

* **Redes externas** (criadas no setup):

  * `proxy` → conecte o **nginx** do projeto para expor via Traefik (labels + `traefik.docker.network=proxy`).
  * `db` → conecte o **php** do projeto quando usar o **MySQL central**.
* **Labels Traefik** por projeto (exemplo):

  * `traefik.enable=true`
  * `traefik.http.routers.<cliente>-<projeto>.rule=Host(\`\<domínio>\`)\`
  * `traefik.http.routers.<cliente>-<projeto>.entrypoints=websecure`
  * `traefik.http.routers.<cliente>-<projeto>.tls.certresolver=le`
  * `traefik.http.routers.<cliente>-<projeto>.middlewares=<canonical>`
  * `traefik.http.services.<cliente>-<projeto>.loadbalancer.server.port=80`
  * `traefik.docker.network=proxy`

---

## 🧰 Comandos úteis

**Traefik (Swarm):**

```bash
docker stack ls
docker stack ps traefik
docker service ls
docker service logs -f traefik_traefik
docker stack deploy -c /opt/traefik/stack.yml traefik
docker stack rm traefik
```

**Projeto (Compose):**

```bash
docker compose -f /home/<cliente>/<projeto>/docker-compose.yml ps
docker compose -f /home/<cliente>/<projeto>/docker-compose.yml up -d
docker compose -f /home/<cliente>/<projeto>/docker-compose.yml logs -f nginx
```

---

## 🗺️ Roadmap

* [ ] Templates de queue/cron (Horizon/Supervisord)
* [ ] Rate limit & security headers padrão por serviço
* [ ] Backups automáticos (`auto_backup.sh` + `setup-cron-backups.sh`)
* [ ] **Script complementar de rsync** → para rodar em máquina local/servidor externo, sincronizando apenas alterações a partir de `/opt/rbackup`.
* [ ] Logs centralizados (Loki/Promtail + Grafana)
* [ ] Redis / Meilisearch opcionais
* [ ] Suporte a múltiplos nós Swarm (cluster completo)

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
