# 📘 Documentação do Provisionador — `mkclient`

O **`mkclient`** é o provisionador de projetos/clients dentro da infraestrutura com **Docker + Traefik**.
Ele cria a stack **Nginx + PHP-FPM** por domínio, configura banco (SQLite ou MySQL central), gera arquivos (.env, Dockerfiles e **Compose ou Stack Swarm**), sobe os serviços e aplica ajustes padrão para apps **Laravel**.

A partir desta versão, o `mkclient` foi **refatorado em etapas (steps)** e ganhou:

* **Modo de deploy**: escolha entre **Docker Compose** ou **Docker Swarm (stack)**;
* **Perfis PHP automáticos** (mínimo/completo via inspeção do `composer.json`);
* **Wizard com validações** (DNS → IP da VPS, Git/SSH);
* Execução de **Composer/Artisan unificada** (funciona em Compose e Swarm).

---

## ✅ Pré-requisitos

* VPS com **Docker** instalado (via [`setup.sh`](setup.md)).

  * Para **Swarm**: o nó deve estar com `docker swarm init` (a infra pode fazer isso para você).
* Infra do **Traefik** já instalada em `/opt/traefik`, com:

  * redes externas compartilhadas: `proxy` (sempre) e `db` (se usar MySQL);
  * arquivo `/opt/traefik/.env` (se usar MySQL central, precisa conter **`MYSQL_ROOT_PASSWORD`**).
* **DNS** do domínio do projeto apontando para o IP da VPS (para HTTP-01; com Cloudflare + DNS-01 também funciona).
* (Opcional) **SSH configurado para GitHub** no host (a chave pode ser criada pelo `setup.sh`).

---

## 🧭 Visão geral do fluxo

1. **Coleta inputs e confirma resumo**
   (cliente, projeto, domínio, **modo: Compose/Swarm**, PHP, origem do código, opções Laravel, perfil PHP).
2. **Prepara o ambiente local** (usuário Linux, pastas, redes).
3. **Gera arquivos de suporte** (nginx.conf + templates de Dockerfiles).
4. **Traz o código** (Git/ZIP/vazio).
5. **Detecta perfil PHP pelo `composer.json`** (ou aplica escolha manual).
6. **Configura banco** (cria schema/usuário e importa dump se MySQL).
7. **Gera manifestos de execução**

   * **Compose**: `docker-compose.yml`
   * **Swarm**: `stack.yml` (services com `deploy` e labels Traefik)
8. **Cria/ajusta `.env`.**
9. **Build + subida**

   * **Compose**: `docker compose build php && up -d`
   * **Swarm**: `docker build` da imagem `php` + `docker stack deploy`
   * Dispara emissão do certificado TLS (ACME).
10. **Ajustes Laravel** (composer, key, optimize, migrate/seed, permissões).
11. **Resumo final e dicas de uso** (comandos úteis para Compose/Swarm).

> O `mkclient` salva um **state** em
> `/home/<cliente>/<projeto>/.provision/state.env`
> permitindo **retomar** do ponto desejado.

---

## ▶️ Como executar

Fluxo completo:

```bash
bash /opt/devops-stack/scripts/mkclient.sh
```

Executar **a partir** de um step específico:

```bash
START_AT=50 bash /opt/devops-stack/scripts/mkclient.sh
```

Executar **até** um step e parar:

```bash
STOP_AT=80 bash /opt/devops-stack/scripts/mkclient.sh
```

---

## 🗂️ Estrutura de arquivos

```
scripts/
├─ mkclient.sh                # orquestrador (roda os steps em ordem)
└─ client/
   ├─ lib.sh                  # helpers + persistência de state (Compose/Swarm-aware)
   └─ steps/
      ├─ 10-inputs.sh         # perguntas (inclui modo Compose/Swarm), resumo e confirmação
      ├─ 20-prep.sh           # redes, usuário Linux, pastas
      ├─ 30-nginx-phpfiles.sh # gera nginx.conf + templates de Dockerfiles
      ├─ 40-code.sh           # obtém código (Git/ZIP/vazio)
      ├─ 45-php-profile.sh    # detecta perfil PHP pelo composer.json
      ├─ 50-db.sh             # MySQL: cria DB/usuário e importa dump
      ├─ 60-compose.sh        # (se MODE=compose) gera docker-compose.yml
      ├─ 65-stack.sh          # (se MODE=swarm) gera stack.yml (Docker Swarm)
      ├─ 70-env.sh            # cria/ajusta .env
      ├─ 80-up.sh             # build + up (Compose ou Swarm) + trigger ACME
      ├─ 90-laravel.sh        # composer/key/optimize/migrate/seed/menu (funciona nos 2 modos)
      └─ 99-summary.sh        # resumo e comandos úteis (Compose/Swarm)
```

---

## 📄 O que cada arquivo faz

### `10-inputs.sh` — Inputs e confirmação (com validações)

Pergunta:

* **Cliente, Projeto, Domínio** (valida que o DNS aponta para a VPS, quando possível).
* **Modo de deploy**: **Docker Compose** ou **Docker Swarm** (se o Swarm estiver ativo).
* **Versão do PHP** (8.1/8.2/8.3/8.4; padrão 8.2).
* **DB**: `SQLite` ou `MySQL (central)`.
* **Origem do código**: Git (SSH) / ZIP local / Vazio (lembra de vincular SSH ao GitHub).
* **Execuções Laravel**:

  * Composer install → **produção (--no-dev)** ou **com dev**
  * `migrate`, `seed`, `menu:make`, `viewsmysql:make`
* **Perfil PHP**:

  * **Auto (padrão)**: detecta dependências (ex.: `ext-intl`, Filament).
  * **Manual**: `min` (sem intl) ou `full` (com intl).
* Exibe **resumo** e pede confirmação. Salva o **state**.

### `20-prep.sh` — Preparação do ambiente

* Garante redes Docker externas (`proxy`, `db`).
* Cria usuário Linux `<cliente>` e diretórios (`src`, `nginx`, `.composer-cache`, `.provision`).
* Ajusta permissões.

### `30-nginx-phpfiles.sh` — Geração de arquivos

* Cria `nginx.conf`.
* Gera **templates** de Dockerfiles:

  * `.min.tpl`: pdo\_mysql/sqlite, mbstring, bcmath, gd, zip, exif.
  * `.full.tpl`: tudo do min **+ intl** (icu).

### `40-code.sh` — Origem do código

* **Git SSH** → clona repo (opcionalmente branch).
* **ZIP** → extrai.
* **Vazio** → mantém diretório para subir depois.

### `45-php-profile.sh` — Perfil PHP

* Analisa `composer.json`:

  * Se detectar `ext-intl` / `filament/*` / `symfony/intl`, força **full**.
  * Senão, mantém **min** (ou o que tiver sido escolhido).

### `50-db.sh` — Banco (MySQL central)

* Cria schema + usuário com senha aleatória.
* Importa dump (`dump.sql` ou `dump.sql.gz`) se presente.
* Marca `DUMP_IMPORTED=1` e remove o dump da pasta `src/`.

### `60-compose.sh` — Manifesto Compose (MODE=compose)

* Copia o template correto para `php.mysql.Dockerfile` ou `php.sqlite.Dockerfile`.
* Gera `docker-compose.yml` com `php` + `nginx` e **labels Traefik**.

### `65-stack.sh` — Manifesto Swarm (MODE=swarm)

* Copia o template correto para o Dockerfile final.
* Gera `stack.yml` (versão 3.9) com `deploy`, **labels Traefik** no serviço `nginx`
  e `networks` (`proxy`, `app`, `db` se necessário).

### `70-env.sh` — `.env`

* Cria/ajusta `.env` com dados do projeto (SQLite **ou** MySQL).

### `80-up.sh` — Subida inicial (Compose **ou** Swarm)

* **Compose**: `docker compose build php && docker compose up -d`.
* **Swarm**: `docker build -t <cliente>_<projeto>_php:latest ... && docker stack deploy -c stack.yml <stack>`.
* Dispara emissão de certificado (ACME) e aguarda.

### `90-laravel.sh` — Ajustes Laravel

* Garante `database.sqlite` se SQLite.
* **Composer install**:

  * Pula se ZIP trouxe `vendor/` + `composer.lock`.
  * Caso contrário, executa conforme seleção (produção ou dev).
* **Laravel tasks**:

  * `key:generate`, `dump-autoload -o`, `optimize`, `storage:link`.
  * `viewsmysql:make` / `menu:make` (se selecionados).
  * `migrate` / `seed` (se selecionados; **pulados** se dump importado).
* Ajusta permissões (`storage`, `bootstrap/cache`).

### `99-summary.sh` — Resumo

* Mostra caminhos úteis, credenciais DB (se MySQL), perfil PHP aplicado e opções Laravel.
* Exibe **comandos diferentes para Compose e Swarm**.

---

## 📦 Estrutura final por projeto

```
/home/<cliente>/<projeto>/
├── src/
├── nginx/
│   └── nginx.conf
├── php.sqlite.Dockerfile(.tpls)
├── php.mysql.Dockerfile(.tpls)
├── docker-compose.yml        # (se MODE=compose)
├── stack.yml                 # (se MODE=swarm)
├── .composer-cache/
└── .provision/
    └── state.env
```

> Os `.tpl` são templates internos; os steps **60/65** geram o Dockerfile final usado no build.

---

## 🔐 Notas de segurança

* `APP_ENV=production`, `APP_DEBUG=false` por padrão.
* Dumps importados são **apagados** de `src/` após sucesso.
* Credenciais MySQL são geradas automaticamente — **guarde as exibidas no resumo**.
* Restrinja acesso ao dashboard do Traefik conforme necessário (BasicAuth / IP allowlist).

---

## 🧰 Operações do dia a dia

### Ver logs do Nginx

**Compose:**

```bash
docker compose -f /home/<cliente>/<projeto>/docker-compose.yml logs -f nginx
```

**Swarm:**

```bash
docker service logs -f <stack>_nginx
# listar serviços do stack:
docker service ls | grep '^<stack>_'
```

### Rebuild do PHP

**Compose:**

```bash
cd /home/<cliente>/<projeto>
docker compose build php && docker compose up -d
```

**Swarm (rebuild + redeploy):**

```bash
cd /home/<cliente>/<projeto>
docker build -t <cliente>_<projeto>_php:latest -f php.mysql.Dockerfile .   # ou php.sqlite.Dockerfile
docker stack deploy -c stack.yml <stack>
```

### Testar HTTPS

```bash
curl -I https://<dominio>
```

---

## ❓ FAQ rápido

**Posso retomar depois de um erro?**
Sim. Use `START_AT` para recomeçar do step desejado. O `state.env` mantém o contexto.

**Quando as migrations/seeders rodam?**
Somente se selecionadas nos inputs — e **não** roda se um dump foi importado.

**Como sei se preciso do perfil completo (intl)?**
Se usar **Filament**, `ext-intl` ou libs de internacionalização (`symfony/intl`), o `mkclient` detecta e aplica **full** automaticamente (ou você pode forçar manualmente).

**Compose ou Swarm — qual usar?**
Compose é direto e ótimo para 1 VPS. Swarm traz orquestração (replicas, atualização por stack) e organiza melhor múltiplos projetos. O wizard ajuda a decidir.

**O que o script não faz?**
Não cria a infra do Traefik (isso é do `setup.sh`), não gerencia DNS e não implementa deploy contínuo (CI/CD).
