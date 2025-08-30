# 🔐 Checklist de Verificação de Segurança (pós-instalação)

Após provisionar a **infraestrutura** ou um **novo projeto** com o setup, execute esta checagem básica:

---

## 🔎 Rede & Firewall (na VPS)

- [ ] **Conferir portas expostas:**
  ```bash
  ss -ltnp
  ```
  ➡️ Deve aparecer apenas `22`, `80`, `443`.
  
  **Exemplo de saída correta:**
  ```
  LISTEN    0    128    0.0.0.0:22     0.0.0.0:*    users:(("sshd",pid=998))
  LISTEN    0    4096   0.0.0.0:80     0.0.0.0:*    users:(("docker-proxy",pid=282764))
  LISTEN    0    4096   0.0.0.0:443    0.0.0.0:*    users:(("docker-proxy",pid=282778))
  ```

- [ ] **Listar regras de firewall/Docker:**
  ```bash
  iptables -L -n -v
  iptables -t nat -L -n -v
  ```
  ➡️ Confirmar DNAT apenas para Traefik (80/443).
  
  **Procure por estas regras NAT:**
  ```
  DNAT  tcp  --  !br-xxxxx *  0.0.0.0/0  0.0.0.0/0  tcp dpt:80 to:172.18.0.2:80
  DNAT  tcp  --  !br-xxxxx *  0.0.0.0/0  0.0.0.0/0  tcp dpt:443 to:172.18.0.2:443
  ```

---

## 🔑 Acesso SSH (na VPS)

- [ ] **Validar se somente usuários autorizados têm shell:**
  ```bash
  cat /etc/passwd | grep bash
  ```
  
  **Exemplo - revisar usuários com acesso shell:**
  ```
  root:x:0:0:root:/root:/bin/bash
  debian:x:1000:1000:Debian:/home/debian:/bin/bash
  cliente1:x:1001:1001::/home/cliente1:/bin/bash
  ```
  ⚠️ **Verificar se todos os usuários são conhecidos e autorizados.**

---

## 🐳 Containers (na VPS)

- [ ] **Listar containers em execução:**
  ```bash
  docker ps
  ```
  ➡️ Apenas o **Traefik** deve publicar portas externas.  
  ➡️ Apps/bancos devem ficar em rede interna.
  
  **Exemplo de saída segura:**
  ```
  traefik         0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
  nginx           80/tcp (sem bind externo)
  mysql           3306/tcp (sem bind externo)
  phpmyadmin      80/tcp (sem bind externo)
  ```

- [ ] **Inspecionar rede do Traefik:**
  ```bash
  docker network inspect proxy
  ```
  ➡️ Confirmar que os serviços estão ligados na rede `proxy`.
  
  **Verificar se todos os containers necessários estão conectados:**
  ```json
  "Containers": {
    "traefik": {"IPv4Address": "172.18.0.2/16"},
    "nginx": {"IPv4Address": "172.18.0.4/16"},
    "phpmyadmin": {"IPv4Address": "172.18.0.3/16"}
  }
  ```

---

## 📦 Sistema (na VPS)

- [ ] **Conferir pacotes atualizados:**
  ```bash
  apt update && apt upgrade -s
  ```
  
  **Saída ideal:**
  ```
  0 packages can be upgraded.
  ```
  
  **Se houver atualizações pendentes:**
  ```
  X packages can be upgraded. Run 'apt list --upgradable'
  ```
  ➡️ Execute `apt upgrade` para aplicar atualizações de segurança.

- [ ] **Validar espaço em disco:**
  ```bash
  df -h
  ```
  
  **Verificar uso do disco principal:**
  ```
  /dev/sda1    394G  6.6G  371G   2% /
  ```
  ⚠️ **Alertar se uso > 80% em qualquer partição crítica.**

---

## 🔐 Boas práticas (na VPS)

- [ ] **Fail2Ban ativo** para SSH (proteção contra brute force)
- [ ] **Dashboard do Traefik protegido** com senha (BasicAuth)
- [ ] **Backups confirmados:**
  - `/opt/traefik/letsencrypt/acme.json` (certificados)
  - `/opt/traefik/mysql-data` ou `database.sqlite`
  - Código em `/home/<cliente>/<projeto>/`

---

## 🌍 Testes externos (da máquina local)

- [ ] **Rodar um scan de portas abertas:**
  ```bash
  nmap -Pn -p- SEU.IP.VPS
  ```
  ➡️ Deve listar apenas `22`, `80`, `443`.
  
  **Exemplo de saída segura:**
  ```
  PORT    STATE SERVICE
  22/tcp  open  ssh
  80/tcp  open  http
  443/tcp open  https
  ```

- [ ] **Testar resolução DNS:**
  ```bash
  dig +short seu-dominio.com
  ```
  ➡️ Deve apontar para o IP da VPS.
  
  **Exemplo:**
  ```
  72.60.57.232
  ```
  
  📝 **Nota:** Se usar Cloudflare Proxy, aparecerão IPs do Cloudflare (normal).
  ```
  104.21.68.38
  172.67.186.81
  ```

- [ ] **Testar conexão HTTPS:**
  ```bash
  curl -I https://seu-dominio.com
  ```
  ➡️ Deve responder `HTTP/2 200` ou `301/302` conforme redirecionamento configurado.
  
  **Exemplo de resposta saudável:**
  ```
  HTTP/2 200
  server: nginx
  content-type: text/html
  ```

- [ ] **Validar certificado SSL:**
  ```bash
  echo | openssl s_client -connect seu-dominio.com:443 -servername seu-dominio.com | openssl x509 -noout -dates -issuer -subject
  ```
  ➡️ Confirmar validade e emissor correto (Let's Encrypt).
  
  **Exemplo de certificado válido:**
  ```
  notBefore=Aug 29 12:00:00 2025 GMT
  notAfter=Nov 27 11:59:59 2025 GMT
  issuer=C = US, O = Let's Encrypt, CN = R3
  subject=CN = seu-dominio.com
  ```

---

✅ **Rodar este checklist garante que a VPS está segura e pronta para produção.**