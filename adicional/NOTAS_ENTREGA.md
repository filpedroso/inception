# Inception: notas para a entrega

Estado em 2026-10-28. Arquivo pessoal: **não levar para o repo da vogsphere**.

## 1. Mudanças feitas e como explicar

- **Estrutura**: `src/` virou `srcs/requirements/{mariadb,nginx,wordpress}/` (`Dockerfile`, `conf/`, `tools/`) e o Makefile foi para a raiz. Segue o exemplo do subject.
- **Docs**: `README.md`, `USER_DOC.md` e `DEV_DOC.md`, em inglês (capítulos VI e VII do subject).
- **MariaDB, primeira execução**: o servidor temporário em background + loop de ping saiu; entrou o `mariadbd --bootstrap`.
  - O bootstrap sobe sem rede e sem socket, executa o SQL do stdin (heredoc) e sai sozinho. Não há nada para esperar nem matar.
  - O `FLUSH PRIVILEGES` no início é obrigatório: em bootstrap as tabelas de permissão não vêm carregadas, e sem ele `ALTER USER`, `CREATE USER` e `GRANT` falham.
  - Depois, `exec mariadbd` vira o PID 1.
- **WordPress, espera pelo banco**: o loop `until ... sleep 1` saiu.
  - No lugar dele: healthcheck no mariadb + `depends_on: condition: service_healthy` no wordpress. A espera passa a ser feita pelo Docker, fora do entrypoint.
  - No reboot, o Docker religa os containers sem ordem. Se o banco não responder, o `wp` falha, o `set -e` encerra o script e o `restart: always` tenta de novo.
- **Healthcheck**: faz o ping com o usuário da aplicação.
  - Pingando como root sem senha, o log enchia de `Access denied`.
  - O `$$` faz a variável ser expandida dentro do container, então a senha não fica na config (`docker inspect`).
- **Tag das imagens**: `mariadb:inception`, `wordpress:inception`, `nginx:inception`.
  - Sem tag, a imagem vira `:latest`, que é proibido.
  - A tag explícita também evita sobrescrever imagens oficiais do Docker Hub de mesmo nome.
  - A regra da "penúltima estável" vale só para o `FROM`.
- **Portas** (para o item "Configuration modification" da régua, em que o avaliador pede para trocar a porta de um serviço):
  - `NGINX_PORT` e `MYSQL_PORT` no `.env`. O MariaDB recebe a porta por `--port` no entrypoint, e o compose publica `NGINX_PORT`.
  - A cada start, o entrypoint do WordPress reescreve o que a instalação gravou nos volumes: o `DB_HOST` no `wp-config.php` e a URL do site (`home`/`siteurl`) no banco. Sem isso, a troca da porta do banco quebraria a conexão, e a troca da porta do nginx faria o WP redirecionar o navegador para a porta antiga.
  - O que editar em cada serviço está na seção "Changing a port" do DEV_DOC.
  - Entrou o pacote `php83-tokenizer`: o `wp config set` usa `token_get_all()` para editar o `wp-config.php` com segurança (o `wp config create` só gera o arquivo e não precisa dele). Sem o pacote, o `wp` morria com exit 255 e o container entrava em loop de restart.
  - Pegadinha: uma variável **exportada no shell** (ex.: `export NGINX_PORT=443`) tem prioridade sobre o `.env` na interpolação do compose. Na defesa, só editar o `.env`.
- **Mantido de propósito**: `--skip-test-db`. Ele evita o banco `test` **e** os usuários anônimos (`''@localhost`), que roubariam o login local do `wpuser@'%'`. O `--skip-auth-anonymous-user` foi testado e descartado: não existe no MariaDB 11.4.
- **Sem mudança**: `srcs/.env` com senhas (este repo é pessoal), `DATA_DIR` com o caminho do Mac, `alpine:3.23`.

## 2. Testes já feitos (WSL, do zero)

- **Subida**: `make` sobe na ordem certa e `https://<dominio>` responde 200.
- **TLS e portas**: 1.0 e 1.1 recusados; nginx só escuta na 443.
- **PID 1**: `mariadbd`, `php-fpm` e `nginx` em cada container.
- **Banco**: root sem senha é negado; `wpuser` entra local e pela rede; nenhum usuário anônimo.
- **Usuários do WP**: `jacare` (administrator) e `autor` (author).
- **Persistência**: o conteúdo sobrevive a `make down` + `make`.
- **Recuperação**: crash do nginx reinicia sozinho; subida fora de ordem se recupera.
- **Troca de portas** (2026-11-08): nginx 443→8443, MariaDB 3306→3307 e php-fpm 9000→9001, cada uma só com as edições do DEV_DOC + `make`. O site continuou funcionando, o `/wp-admin/` redirecionou para a porta nova e a 443 parou de responder. Depois, a volta ao padrão funcionou, com o post intacto.

## 3. Checklist da entrega

### VM
- [ ] Criar uma VM Linux (Debian/Ubuntu) com Docker Engine + plugin Compose, make e git; colocar o usuário no grupo `docker`.
- [ ] Adicionar `127.0.0.1 <login>.42.fr` no `/etc/hosts` da VM.

### Versões
- [ ] Conferir <https://alpinelinux.org/releases/>. Se a 3.25 já saiu (esperada por volta de dez/2026), a penúltima passa a ser a **3.24**. Trocar em:
  - os 3 Dockerfiles;
  - `CLEANER` no Makefile;
  - o README ("`alpine:3.23` ... penultimate").
- [ ] Se trocar o Alpine, conferir em <https://pkgs.alpinelinux.org> se `php83` existe na branch nova. Se não existir, ajustar a versão do PHP em:
  - Dockerfile do wordpress (pacotes, `/etc/php83/`, symlink);
  - `tools/entrypoint.sh` (`php-fpm83`);
  - README e DEV_DOC ("PHP 8.3").
- [ ] Se trocar o Alpine, rodar `SELECT user,host FROM mysql.user` e conferir que não há usuário vazio.

### Login e caminhos
- [ ] Confirmar o login da 42 (assumido `fpedroso`).
- [ ] No `srcs/.env`: `DATA_DIR=/home/<login>/data` e `DOMAIN_NAME=<login>.42.fr`.
- [ ] Se o login não for `fpedroso`, trocar também em:
  - `conf/nginx.conf` (`server_name`);
  - Dockerfile do nginx (CN do certificado);
  - README, USER_DOC e DEV_DOC.

### Repo da vogsphere
- [ ] Levar só `Makefile`, `srcs/` (sem `.env`), `README.md`, `USER_DOC.md` e `DEV_DOC.md`, num histórico novo: o `.env` está em 3 commits deste repo.
- [ ] Não levar `srcs/.env`, `exercises/`, `en.subject.pdf` nem este arquivo.
- [ ] Criar um `.gitignore` com `srcs/.env` (e `secrets/`, se usar secrets).
- [ ] Antes do push, fazer um `grep` pelas senhas e pelo `.env` no repo inteiro.
- [ ] Na VM: `git clone` (garante LF; não copiar do Windows) e criar o `srcs/.env` a partir do modelo do DEV_DOC.
- [ ] README: revisar a seção "Use of AI" e acrescentar outros usos de IA, se houver.

### Ensaio antes da defesa
- [ ] Limpar tudo no Docker (containers, imagens, volumes, redes), apagar o conteúdo de `/home/<login>/data` e rodar `make` do zero.
- [ ] Site abre sem a tela de instalação; `http://` não abre; só TLS 1.2 e 1.3.
- [ ] `docker volume inspect` mostra `/home/<login>/data/...`.
- [ ] Entrar no admin; comentar com o author; editar uma página como admin.
- [ ] Entrar no banco como root (`docker exec -it mariadb mariadb -u root -p`).
- [ ] Reiniciar a VM, rodar `make` e conferir que tudo volta com os dados.
- [ ] Ensaiar a troca de porta dos 3 serviços (seção "Changing a port" do DEV_DOC): editar, rodar `make` e conferir o site. Com nginx fora da 443, o acesso é `https://<login>.42.fr:<porta>`.
- [ ] Saber explicar cada linha: a régua pede uma modificação ao vivo, e se ela não funcionar a avaliação acaba.

## 4. Melhorias a discutir

- Docker secrets para as senhas (o subject só "strongly recommends"). **Decidido (2026-11-08): não usar.** O `srcs/.env` com as senhas fica fora do git e é criado na VM para a avaliação. Na defesa, justificar com a comparação "Secrets vs Environment Variables" do README.
  - Confirmado na régua (preliminares): *"the use of a local .env file to store info is allowed, and/or also the use of docker secrets"*. Só reprova se houver senha no repositório git.
- `.gitattributes` com `* text=auto eol=lf`, para o checkout no Windows não gerar CRLF.
- Domínio vindo do `.env` em vez de fixo no `nginx.conf` e no Dockerfile.

## 5. Como testar no WSL (rede da empresa)

- **Cópia em LF**: copiar o projeto para `~` (não rodar de `/mnt/c`) e converter: `find . -type f -exec sed -i 's/\r$//' {} +`.
- **Pasta de dados**: na cópia, apontar `DATA_DIR` para uma pasta de teste.
- **Proxy da empresa**: ele intercepta HTTPS (CA `MRV-PKI-CA`). Só na cópia:
  1. Extrair a CA: `echo | openssl s_client -connect dl-cdn.alpinelinux.org:443 -showcerts | awk '/BEGIN CERT/,/END CERT/' > mrv-ca.crt`.
  2. Copiar o `mrv-ca.crt` para a pasta de cada serviço.
  3. Logo após o `FROM`, adicionar `COPY mrv-ca.crt /usr/local/share/ca-certificates/` e `RUN cat /usr/local/share/ca-certificates/mrv-ca.crt >> /etc/ssl/certs/ca-certificates.crt`.
- **Sem /etc/hosts**: `curl -k --resolve <dominio>:443:127.0.0.1 https://<dominio>/`.
- **Ao terminar**: `make fclean` e apagar a cópia (com `restart: always`, a stack sobe sozinha e ocupa a 443).
