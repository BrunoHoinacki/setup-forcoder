# 📘 Documentação do Provisionador — `mkclient`

O **`mkclient`** é o provisionador de projetos/clients dentro da infraestrutura com **Docker + Traefik**.
Ele cria a stack **Nginx + PHP-FPM** por domínio, configura banco (SQLite ou MySQL central), gera arquivos (.env, Dockerfiles, compose), sobe os containers e aplica ajustes padrão para apps **Laravel**.

A partir desta versão, o `mkclient` foi **refatorado em etapas (steps)** para facilitar manutenção e depuração.
Também foi adicionado suporte a **perfis PHP automáticos** (mínimo ou completo, com base no `composer.json`).

---

## ✅ Pré-requisitos

* VPS com Docker & Docker Compose (instalados via [setup.sh](setup.md)).
* Infra do **Traefik** já instalada em `/opt/traefik`, com:

  * redes externas compartilhadas: `proxy` (sempre) e `db` (se usar MySQL);
  * arquivo `/opt/traefik/.env` com variáveis (se usar MySQL central, **`MYSQL_ROOT_PASSWORD`** precisa existir).
* DNS do domínio do projeto apontando para a VPS.
* (Opcional) SSH configurado para **Git (SSH)** no host.

---

## 🧭 Visão geral do fluxo

1. **Coleta inputs e confirma resumo.**
2. **Prepara o ambiente local** (usuário Linux, pastas, redes).
3. **Gera arquivos de suporte** (nginx.conf + templates de Dockerfiles).
4. **Traz o código** (Git/ZIP/vazio).
5. **Detecta perfil PHP pelo `composer.json`** (ou aplica escolha manual).
6. **Configura banco** (cria schema/usuário e importa dump se MySQL).
7. **Gera `docker-compose.yml` aplicando o Dockerfile correto.**
8. **Cria/ajusta `.env`.**
9. **Build + `up -d` da stack + trigger do certificado.**
10. **Ajustes Laravel** (composer, key, optimize, migrate/seed, permissões).
11. **Resumo final e dicas de uso.**

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

> O `mkclient` salva um **state** em:
> `/home/<cliente>/<projeto>/.provision/state.env`
> Isso permite **retomar** sem perder contexto.

---

## 🗂️ Estrutura de arquivos

```
scripts/
├─ mkclient.sh                # orquestrador (roda os steps em ordem)
└─ client/
   ├─ lib.sh                  # helpers + persistência de state
   └─ steps/
      ├─ 10-inputs.sh         # perguntas, resumo e confirmação
      ├─ 20-prep.sh           # redes, usuário Linux, pastas
      ├─ 30-nginx-phpfiles.sh # gera nginx.conf + templates de Dockerfiles
      ├─ 40-code.sh           # obtém código (Git/ZIP/vazio)
      ├─ 45-php-profile.sh    # detecta perfil PHP pelo composer.json
      ├─ 50-db.sh             # MySQL: cria DB/usuário e importa dump
      ├─ 60-compose.sh        # aplica template certo e gera docker-compose.yml
      ├─ 70-env.sh            # cria/ajusta .env
      ├─ 80-up.sh             # build php + up -d + trigger ACME
      ├─ 90-laravel.sh        # composer/key/optimize/migrate/seed/menu
      └─ 99-summary.sh        # resumo e comandos úteis
```

---

## 📄 O que cada arquivo faz

### `10-inputs.sh` — Inputs e confirmação

Pergunta:

* **Cliente, Projeto, Domínio**
* **Versão do PHP** (8.1 / 8.2 / 8.3 / 8.4, padrão 8.2)
* **DB**: `SQLite` ou `MySQL (central)`
* **Origem do código**: Git (SSH) / ZIP local / Vazio
* **Execuções opcionais do Laravel**:

  * Composer install em **produção (--no-dev)** ou **com dev**
  * Rodar `migrate`
  * Rodar `seed`
  * Rodar `menu:make`
  * Rodar `viewsmysql:make`
* **Perfil PHP**:

  * **Auto (padrão)**: detecta dependências no `composer.json`.
  * **Manual**: usuário pode escolher `min` (sem intl) ou `full` (com intl).
* Mostra **resumo** e pede confirmação.
* Salva state inicial.

### `20-prep.sh` — Preparação do ambiente

* Garante redes Docker externas (`proxy`, `db` se MySQL).
* Cria usuário Linux `<cliente>`.
* Prepara diretórios (`src`, `nginx`, `.composer-cache`, `.provision`).
* Ajusta permissões.

### `30-nginx-phpfiles.sh` — Geração de arquivos

* Cria `nginx.conf`.
* Gera **templates** de Dockerfiles:

  * `.min.tpl`: apenas extensões essenciais (pdo\_mysql, sqlite, mbstring, bcmath, gd, zip, exif).
  * `.full.tpl`: inclui também suporte a `intl` (icu-libs + intl).

### `40-code.sh` — Origem do código

* **Git SSH** → clona repo.
* **ZIP** → extrai.
* **Vazio** → mantém diretório para subir depois.

### `45-php-profile.sh` — Perfil PHP

* Analisa `composer.json`:

  * Se encontrar `ext-intl`, `filament/*` ou `symfony/intl`, força perfil **full**.
  * Senão, mantém **min**.
* Exporta `PHP_PROFILE` para os próximos steps.

### `50-db.sh` — Banco (MySQL central)

* Cria schema + usuário.
* Importa dump (`dump.sql(.gz)`) se presente, marcando `DUMP_IMPORTED=1`.

### `60-compose.sh` — docker-compose.yml

* Copia o **template** escolhido para `php.mysql.Dockerfile` ou `php.sqlite.Dockerfile`.
* Gera `docker-compose.yml` com serviços `php` + `nginx` e labels Traefik.

### `70-env.sh` — .env

* Cria/ajusta `.env` com dados do projeto.

### `80-up.sh` — Subida inicial

* Builda container PHP com Dockerfile escolhido.
* Sobe stack.
* Dispara emissão de certificado SSL.

### `90-laravel.sh` — Ajustes Laravel

* Garante `database.sqlite` se SQLite.
* **Composer install**:

  * Pula se ZIP trouxe `vendor/` + `composer.lock`.
  * Caso contrário, roda conforme escolha (produção ou dev).
* **Laravel tasks**:

  * `php artisan key:generate`, `dump-autoload -o`, `optimize`, `storage:link`.
  * Rodar `viewsmysql:make` se escolhido.
  * Rodar `menu:make` se escolhido.
  * Rodar `migrate` / `seed` se escolhidos (pulados se dump importado).
* Ajusta permissões (`storage`, `bootstrap/cache`).

### `99-summary.sh` — Resumo

* Mostra caminhos úteis, credenciais DB, perfil PHP aplicado e opções Laravel selecionadas.

---

## 📦 Estrutura final por projeto

```
/home/<cliente>/<projeto>/
├── src/
├── nginx/
│   └── nginx.conf
├── php.sqlite.Dockerfile(.tpls)
├── php.mysql.Dockerfile(.tpls)
├── docker-compose.yml
├── .composer-cache/
└── .provision/
    └── state.env
```

> Os `.tpl` são templates internos; o step `60` gera o Dockerfile final usado no build.

---

## 🔐 Notas de segurança

* `APP_ENV=production`, `APP_DEBUG=false` por padrão.
* Dumps importados são **apagados** de `src/` após sucesso.
* Credenciais MySQL geradas automaticamente — guarde as exibidas no resumo.

---

## 🧰 Operações do dia a dia

Logs do Nginx:

```bash
docker compose -f /home/<cliente>/<projeto>/docker-compose.yml logs -f nginx
```

Rebuild do PHP:

```bash
cd /home/<cliente>/<projeto>
docker compose build php && docker compose up -d
```

Testar HTTPS:

```bash
curl -I https://<dominio>
```

---

## ❓FAQ rápido

* **Posso retomar depois de um erro?**
  Sim. Use `START_AT` para recomeçar do ponto desejado.

* **Quando as migrations/seeders rodam?**
  Apenas se selecionados nos inputs, e não houver dump importado.

* **Como sei se preciso do perfil completo?**
  Se usar **Filament**, `ext-intl` ou libs de internacionalização (`symfony/intl`), o `mkclient` já detecta automaticamente.

* **Posso forçar manualmente o perfil PHP?**
  Sim, basta recusar a detecção automática no `10-inputs.sh`.

* **O que o script não faz?**
  Não cria a infra do Traefik (isso é do `setup.sh`), não gerencia DNS e não faz deploy contínuo.