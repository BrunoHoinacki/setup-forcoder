# SetupForcoder

<a href="https://setup.forcoder.com.br">
  <img src="assets/banners/banner1.png" alt="SetupForcoder" width="1440">
</a>

**Deploy automatizado de aplicações Laravel em Docker Swarm, com Traefik + SSL via Cloudflare.**
Open-source, direto ao ponto — feito para simplificar a vida no servidor. 🚀

---

## 🔥 O que é

O **SetupForcoder** transforma uma VPS Ubuntu em um ambiente pronto para produção:

* 🐳 **Docker Engine + Compose plugin**
* ⚡ **Docker Swarm** inicializado e rede overlay
* 🧭 **Traefik** como reverse proxy + **SSL automático** (ACME DNS-01 via Cloudflare)
* 📂 Estrutura padrão em **`/workspace`** para múltiplos projetos Laravel
* ✉️ **SMTP** e **DNS** configuráveis por app
* 🧰 **Menu interativo** no instalador principal (`Setup`)
* 🛠️ **Makefile** com targets (`traefik:deploy`, `app:new`, etc.)

---

## 📌 Requisitos

* Ubuntu **22.04+** (recomendado **24.04**)
* VPS com pelo menos **2 vCPU / 4 GB RAM**
* Domínio na **Cloudflare** e **token** com permissão **Zone.DNS Edit**
* Servidor **limpo (fresh install)** para evitar conflitos

> **Portas liberadas**: `22`, `80`, `443`, `2377/tcp`, `7946/tcp+udp`, `4789/udp`

---

## 💿 Instalação rápida

Na VPS (como **root**):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/BrunoHoinacki/setup-forcoder/main/SetupForcoder)
```

> 💡 Enquanto estiver desenvolvendo/testando, use a dica anti-cache:
>
> ```bash
> bash <(curl -fsSL "https://raw.githubusercontent.com/BrunoHoinacki/setup-forcoder/main/SetupForcoder?$(date +%s)")
> ```

Após finalizar:

```bash
make traefik:deploy
make app:new
```

---

## 🧭 Fluxo de instalação

1. **Bootstrap (`SetupForcoder`)**

   * Atualiza pacotes essenciais
   * Baixa e executa o **instalador principal** (`Setup`)

2. **Instalador principal (`Setup`)**

   * Menu interativo com opções:

     * Dependências (`curl`, `unzip`, `ufw`, `rsync`, etc.)
     * **Docker Engine** + Compose plugin
     * **Docker Swarm** + rede overlay (`edge`)
     * Cria diretório **`/workspace`**
     * Baixa e expande o **pacote de infra** em `/opt/forcoder/infra`

3. **Make targets** (em `/opt/forcoder/infra`)

   * `make traefik:deploy` → sobe Traefik com ACME/Cloudflare
   * `make app:new` → wizard para criar app Laravel (domínio, SMTP, DB, etc.)

---

## ⚙️ Variáveis & Diretórios

* **Workspace padrão**: `/workspace`
* **Infra expandida**: `/opt/forcoder/infra`
* **Rede overlay (Swarm)**: `edge`
* **Timezone**: `America/Sao_Paulo`

`.env` da infra contém:

* `CF_API_TOKEN` (Cloudflare, com **Zone.DNS Edit**)
* `CF_ZONE_ID`
* `ACME_EMAIL`

---

## 🧪 Modo de teste (mock)

Para simular sem mexer no sistema:

```bash
RUN_MODE=mock ./Setup
```

O menu executa as mesmas etapas, mas sem efeitos reais.
Útil para validar logs e fluxo antes de usar em produção.

---

## 🆘 Solução de problemas

* **APT travado**
  O `Setup` já tenta destravar. Manualmente:

  ```bash
  rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock-frontend
  dpkg --configure -a
  apt-get update
  ```

* **UFW**
  As regras são adicionadas, mas o firewall não é habilitado por padrão.
  Se quiser ativar: `ufw enable` (garanta que as portas listadas estejam liberadas).

* **Cache do GitHub raw**
  Use a flag com timestamp mostrada na instalação rápida.

* **DNS/SSL**
  Garanta que o token da Cloudflare tenha permissão **Zone.DNS Edit**
  e que o domínio esteja apontando para a zona correta.

---

## 🧱 Estrutura do repo

```
setup-forcoder/
├─ LICENSE.txt
├─ README.md
├─ Setup             # Instalador principal (menu, swarm, overlay, workspace, infra)
├─ SetupForcoder     # Bootstrap inicial
├─ Makefile          # Targets: traefik:deploy, app:new, etc.
├─ stacks/           # Stacks Docker (traefik, laravel, nginx, etc.)
├─ scripts/          # Scripts auxiliares (lib.sh, app_new.sh)
└─ assets/           # Banners/imagens
```

---

## 🤝 Contribuindo

Projeto **open-source**. PRs, Issues e feedbacks são super bem-vindos!
Se usar/derivar, dê os créditos para a comunidade **Forcoder** 💙

---

## 📜 Licença

Distribuído sob a **MIT License**. Veja `LICENSE.txt`.

---

## 🔗 Links úteis

* 🌐 Site: [https://www.forcoder.com.br](https://www.forcoder.com.br)
* 🧪 Setup online: [https://setup.forcoder.com.br](https://setup.forcoder.com.br)
* 🐛 Issues: [GitHub Issues](https://github.com/BrunoHoinacki/setup-forcoder/issues)