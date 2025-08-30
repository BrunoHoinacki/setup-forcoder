# ⚙️ `setup.sh` — Setup da Infra (Traefik + Docker) na VPS

O `setup.sh` prepara a **infraestrutura base** da VPS para hospedar múltiplos projetos atrás do **Traefik** com **SSL automático** (Let’s Encrypt).
Também pode subir o **MySQL central (MariaDB)** e **phpMyAdmin** integrados, caso você opte.

> Este script é **modularizado**. O orquestrador `scripts/setup.sh` apenas chama passos em `scripts/setup/steps/` e usa helpers em `scripts/setup/lib.sh`.

---

## 🧭 O que o setup faz

1. **Checagens iniciais**

   * Exige root (`sudo su`).
   * Valida ambiente **Ubuntu/Debian (APT)**.
   * Garante que as portas **80/443** estejam livres.

2. **Coleta de parâmetros**

   * E-mail para **Let’s Encrypt**.
   * **Domínio do dashboard** do Traefik (ex.: `infra.seu-dominio.com.br`).
   * **Cloudflare opcional**:

     * Com **API Token**: usa **DNS-01** (pode manter **proxy laranja ativo**).
     * Sem token: usa **HTTP-01** (deixe **DNS cinza** durante a emissão).
   * **Canonical** (non-www → root **ou** root → www).
   * **BasicAuth** (usuário/senha) do **dashboard**.
   * **MySQL central (opcional)** + **phpMyAdmin**: define/gera senha do root.

3. **Instalações**

   * **Docker** e **Compose** (repo oficial, com fallback para `docker.io`).
   * Abre **UFW** (22, 80, 443) se disponível; inclui usuário no grupo `docker`.

4. **SSH para GitHub (opcional, mas útil para `mkclient.sh`)**

   * Gera **chave ed25519** (se não existir).
   * Mostra a **pública** para você adicionar no GitHub.
   * Testa `ssh -T git@github.com`.

5. **Redes Docker compartilhadas**

   * `proxy` (HTTP/HTTPS via Traefik)
   * `db` (acesso ao MySQL central)

6. **Traefik (tunado)**

   * Prepara `/opt/traefik` com:

     * `letsencrypt/acme.json` (600), `dynamic/`, `mysql-data/` (se usar DB).
     * `.env` com variáveis (LE, domínio, BasicAuth, CF token, etc.).
     * `dynamic/middlewares.yml` com cadeia **canonical + compress + secure-headers**.
   * Gera `docker-compose.yml` com:

     * **HTTP/3 (QUIC)** habilitado (porta `443/udp`).
     * **Redirect global** HTTP→HTTPS no **entrypoint**.
     * **Dashboard** em `https://<domínio>/dashboard` e `/api` com **BasicAuth**.
     * **Headers de segurança** e **compressão** aplicados via middleware global.
     * **AccessLog JSON** em `/opt/traefik/logs/access.json` com filtros (status 4xx/5xx, UA/Referer).
     * **CertResolver** `le` (**DNS-01** Cloudflare **ou** **HTTP-01**).
     * **phpMyAdmin** em subcaminho `/phpmyadmin/` (se habilitado).
     * **Banner de upgrade/check de versão desativados**.

7. **Sobe a stack** (`docker compose up -d`) e exibe **notas finais**.

---

## 🗂️ Estrutura modular

```
scripts/
├─ setup.sh                      # orquestrador (fino)
└─ setup/
   ├─ lib.sh                     # helpers (UI, guards, utils, install docker)
   └─ steps/
      ├─ 10-prereqs.sh           # root/apt/portas, derruba traefik antigo
      ├─ 20-inputs.sh            # perguntas (LE, domínio, CF, BasicAuth, MySQL)
      ├─ 30-install-docker.sh    # instala Docker/compose + ufw + grupo docker
      ├─ 40-ssh-github.sh        # chave SSH e teste com GitHub
      ├─ 50-networks.sh          # cria redes proxy/db
      ├─ 60-traefik-files.sh     # /opt/traefik (.env, middlewares, acme.json)
      ├─ 70-compose.sh           # docker-compose.yml (Traefik + opcional MySQL/PMA)
      ├─ 80-up.sh                # docker compose up -d
      └─ 90-notes.sh             # mensagens finais e dicas
```

---

## ✅ Pré-requisitos

* VPS **Ubuntu/Debian** com root ou `sudo`.
* Apontar **DNS A/AAAA** do **domínio do dashboard** para o IP da VPS.
* Repositório desta infra **já na VPS** (upload via rsync/scp).
* (Opcional) **API Token Cloudflare** com permissão **DNS Edit**, se quiser **DNS-01**.

---

## ▶️ Como rodar

Na VPS:

```bash
sudo -s
cd /opt/devops-stack
bash scripts/setup.sh
```

Responda às perguntas. O script só prossegue no teste do GitHub após você **adicionar** a chave pública na sua conta (caso precise usar Git depois).

---

## 🔐 Cloudflare — como decidir

* **Tem API Token?** Use **DNS-01** (pode manter o **proxy laranja** ligado).
* **Sem token?** Use **HTTP-01** (deixe **DNS cinza** – “DNS only” – até emitir o certificado).

---

## 🔎 Acessos e caminhos

* **Dashboard Traefik:** `https://<DASH_DOMAIN>/dashboard/`
* **phpMyAdmin (opcional):** `https://<DASH_DOMAIN>/phpmyadmin/`
* **Pasta da infra:** `/opt/traefik`
* **Redes Docker:** `proxy` e `db`
* **Logs do Traefik:**

  ```bash
  tail -f /opt/traefik/logs/access.json
  docker logs -f traefik
  ```

---

## 🧰 Troubleshooting rápido

* **Certificado não emite (HTTP-01)**

  * DNS A/AAAA deve apontar corretamente.
  * Deixe **DNS cinza** até emitir.

* **Certificado não emite (DNS-01)**

  * Verifique **API Token** e permissões DNS Edit.

* **phpMyAdmin**

  * Use a **barra final** `/phpmyadmin/` (há redirect automático).

* **Portas 80/443 ocupadas**

  * Pare `apache2`/`nginx` nativos:

    ```bash
    systemctl disable --now apache2 nginx
    ```

---

## 🛡️ Segurança

* **BasicAuth** no dashboard: troque periodicamente.
* Limite IPs (UFW/Nginx/Traefik) para o dashboard, se necessário.
* Mantenha o sistema e imagens atualizados.
* Backups importantes:

  * `/opt/traefik/letsencrypt/acme.json` (certificados)
  * `/opt/traefik/mysql-data` (se usar MySQL)

---

## ➕ Próximos passos (projetos/app)

Com o Traefik pronto, crie stacks de cliente/projeto com:

```bash
bash /opt/devops-stack/scripts/mkclient.sh
```

A documentação do `mkclient.sh` está em [docs/mkclient.md](mkclient.md).