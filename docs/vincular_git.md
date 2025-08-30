# Como gerar e vincular sua chave SSH ao GitHub

Autenticar no GitHub via **SSH** permite clonar, dar **push/pull** com segurança sem digitar senha toda hora. Abaixo, o passo a passo enxuto.

## 1) Verifique se já existe uma chave

```bash
ls -al ~/.ssh
```

Se aparecer `id_ed25519.pub` (ou `id_rsa.pub`), você já tem uma chave pública.

## 2) Gere uma chave nova (recomendado: ed25519)

```bash
ssh-keygen -t ed25519 -C "seu-email@exemplo.com"
```

Sem suporte a ed25519? Use RSA:

```bash
ssh-keygen -t rsa -b 4096 -C "seu-email@exemplo.com"
```

> Dicas:
>
> * Aperte **Enter** para aceitar o caminho padrão (`~/.ssh/id_ed25519`).
> * Passphrase é opcional, mas aumenta a segurança.

## 3) Inicie o agente SSH e adicione a chave

```bash
# iniciar o agente
eval "$(ssh-agent -s)"

# adicionar a chave privada ao agente
ssh-add ~/.ssh/id_ed25519
```

> No Windows (Git Bash), os mesmos comandos funcionam.

## 4) Copie a chave **pública**

```bash
cat ~/.ssh/id_ed25519.pub
```

* macOS: `pbcopy < ~/.ssh/id_ed25519.pub`
* Linux (se tiver xclip): `xclip -sel clip < ~/.ssh/id_ed25519.pub`

## 5) Cadastre no GitHub

GitHub → **Settings** → **SSH and GPG keys** → **New SSH key**
Dê um nome (ex.: “Meu notebook”) e **cole** a chave pública. **Add SSH key**.

## 6) Teste a conexão

```bash
ssh -T git@github.com
```

Na primeira vez, confirme com `yes`. A mensagem esperada é:

```
Hi <seu-usuario>! You've successfully authenticated, but GitHub does not provide shell access.
```

## 7) Use o remoto via SSH no Git

* Ao clonar:

```bash
git clone git@github.com:org/repositorio.git
```

* Para trocar um remoto existente de HTTPS para SSH:

```bash
git remote set-url origin git@github.com:org/repositorio.git
```

---

## Resolução de problemas rápidos

* **Permission denied (publickey)**

  * Confirme que a chave foi adicionada ao agente: `ssh-add -l`
  * Confirme que a **pública** está cadastrada no GitHub.
  * Verifique permissões: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/*`
  * Rode com mais detalhes: `ssh -vT git@github.com`

* **“Host key verification failed”**

  * Aceite a primeira conexão ou adicione o host:
    `ssh-keyscan -t ed25519,ecdsa,rsa github.com >> ~/.ssh/known_hosts`

* **Várias chaves/máquinas**

  * Você pode cadastrar **uma chave por dispositivo** no GitHub.
  * Para usar chave específica:
    `GIT_SSH_COMMAND="ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes" git clone git@github.com:org/repo.git`