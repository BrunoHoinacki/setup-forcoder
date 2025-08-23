<div align="left">
<pre>
███████╗███████╗████████╗██╗   ██╗██████╗     ███████╗ ██████╗ ██████╗  ██████╗ ██████╗ ██████╗ ███████╗██████╗ 
██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗    ██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗
███████╗█████╗     ██║   ██║   ██║██████╔╝    █████╗  ██║   ██║██████╔╝██║     ██║   ██║██║  ██║█████╗  ██████╔╝
╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝     ██╔══╝  ██║   ██║██╔══██╗██║     ██║   ██║██║  ██║██╔══╝  ██╔══██╗
███████║███████╗   ██║   ╚██████╔╝██║         ██║     ╚██████╔╝██║  ██║╚██████╗╚██████╔╝██████╔╝███████╗██║  ██║
╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝         ╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝
</pre>
</div>
                                                                                                                                                        

<p align="center">
  O <b>SetupForcoder</b> é um auto-instalador <b>100% gratuito e open-source</b>, criado para simplificar o deploy de aplicações modernas em uma VPS Ubuntu.
  <br>
  <b>Com ele, você pode rodar múltiplos projetos Laravel em containers Docker, todos atrás de um Traefik com certificados SSL automáticos.</b>
  <br>
  Desenvolvido pela comunidade <b>Forcoder</b>. Se utilizar, <b>dê os créditos</b>! 🚀
</p>
 
---

<h3>📌 Observações e Recomendações</h3>

- Recomendado usar VPS de qualidade como **Contabo**, **Hetzner**, **Hostinger**, **Digital Ocean** ou **AWS**.
- O servidor precisa estar **limpo/fresh install** para evitar conflitos.
- Requisitos mínimos: **Ubuntu 22.04+**, **2 vCPU** e **4GB RAM**. Ajuste conforme a carga e os projetos Laravel que pretende rodar.
- O instalador configura automaticamente:
  - **Docker Engine + Compose plugin**
  - **Docker Swarm + rede overlay**
  - **Traefik** com certificados SSL via **Cloudflare DNS-01**
  - Diretório padrão de projetos em `/workspace`

---

<h3>💿 Como executar o instalador</h3>

<p>Para facilitar, criamos um comando curto que baixa e executa o script do setup. Basta rodar:</p>

```bash
bash <(curl -sSL https://setup.forcoder.com.br)
````

<p>Após isso, o script instalará Docker, inicializará o Swarm e criará a estrutura base. 
Depois é só editar o arquivo <code>.env</code> para colocar as credenciais da Cloudflare e rodar:</p>

```bash
make traefik:deploy
make app:new
```

---

<h3 align="center"><b>Funcionalidades disponíveis</b></h3>
<p align="center">
  🔸 Traefik (reverse proxy + SSL) 🔸 Deploy múltiplos projetos Laravel 🔸 Banco de dados (MySQL por padrão) 🔸 SMTP configurável 🔸 DNS automático via Cloudflare 🔸 Menu interativo para deploy 🔸
</p> 

---

<h3 align="center">📌 Contribuidores</h3>
<p align="center">
  Este projeto é open-source — contribuições são bem-vindas!
</p>

<a align="center" href="https://github.com/forcoder/setup-forcoder/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=forcoder/setup-forcoder" />
</a>

<a href="https://star-history.com/#forcoder/setup-forcoder&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=forcoder/setup-forcoder&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=forcoder/setup-forcoder&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=forcoder/setup-forcoder&type=Date" />
 </picture>
</a>
