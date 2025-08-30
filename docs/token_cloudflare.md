# Como pegar o token na Cloudflare

Cloudflare Dashboard → **(avatar, canto superior direito) My Profile** → **API Tokens** → **Create Token** → **Create Custom Token**:

* **Permissions:**

  * *Zone* → **DNS** → **Edit**
  * (opcional, mas útil) *Zone* → **Zone** → **Read**
* **Zone Resources:**

  * Include → **Specific zone** → selecione a zona do seu domínio (ex.: `forcoder.com.br`)
* **Continue to summary** → **Create Token** → **Copy** (guarde esse valor; é o `CF_DNS_API_TOKEN`).

> Dica: sempre use **API Token** (escopo mínimo), não a Global API Key.
