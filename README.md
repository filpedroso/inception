*This project has been created as part of the 42 curriculum by fpedroso.*

# Inception

## Description

Inception is a system administration project: it sets up a small web infrastructure made of
three services, each one built from its own Dockerfile and running in its own container,
orchestrated with Docker Compose inside a virtual machine.

The result is a WordPress website served over HTTPS at `https://fpedroso.42.fr`:

```
            host (VM)                     Docker network "inception" (bridge)
 browser ──── 443/TLS ────► nginx ──── FastCGI :9000 ────► wordpress ──── SQL :3306 ────► mariadb
                              │                               │                             │
                              └──── wordpress_data ───────────┘                       mariadb_data
                                    (/home/fpedroso/data/wordpress)          (/home/fpedroso/data/mariadb)
```

- **nginx**: the only entry point. Listens on port 443 only, accepts TLSv1.2 and TLSv1.3 only,
  serves static files and forwards PHP requests to WordPress.
- **wordpress**: WordPress + php-fpm (no web server). Installed and configured automatically
  with WP-CLI on the first start.
- **mariadb**: the database server (no web server). Creates the WordPress database and its
  user on the first start.

### Project description

**Use of Docker.** Every service has its own image, built locally from `alpine:3.23` (the
penultimate stable Alpine release at the time of writing). No ready-made service image is
pulled. The Makefile calls Docker Compose, which builds the three images, creates the network
and the two named volumes, and starts the containers with `restart: always`.

**Sources included.**

| Path | Purpose |
|---|---|
| `Makefile` | Entry point: builds and starts everything (`make`), plus stop/clean targets. |
| `srcs/docker-compose.yml` | Services, network, named volumes, healthcheck and startup order. |
| `srcs/.env` | Configuration and credentials (domain, data folder, database and WordPress users). |
| `srcs/requirements/nginx/` | Dockerfile (generates a self-signed certificate) and `conf/nginx.conf`. |
| `srcs/requirements/wordpress/` | Dockerfile (PHP 8.3, php-fpm, WP-CLI), `conf/www.conf` (php-fpm pool) and `tools/entrypoint.sh`. |
| `srcs/requirements/mariadb/` | Dockerfile, `conf/mariadb-server.cnf` (enables networking) and `tools/entrypoint.sh`. |

**Main design choices.**

- **One process per container, as PID 1.** Each entrypoint finishes with `exec`, so the real
  daemon (`mariadbd`, `php-fpm83 -F`, `nginx -g 'daemon off;'`) replaces the shell and receives
  the stop signals directly. No `tail -f`, `sleep infinity` or other keep-alive tricks.
- **MariaDB first-run setup without a background server.** On an empty volume the entrypoint
  runs `mariadb-install-db --skip-test-db` (no test database and no anonymous users), then
  `mariadbd --bootstrap`, which reads the setup SQL from stdin, runs it and exits. Only after
  that is the real server started with `exec`.
- **Startup order through a healthcheck.** MariaDB has a healthcheck (`mariadb-admin ping`) and
  WordPress declares `depends_on: mariadb: condition: service_healthy`, so the WordPress
  container only starts once the database answers. If the database is still unreachable (for
  example after a reboot, when Docker restarts containers in no particular order), a WP-CLI
  command fails, the script exits and `restart: always` tries again.
- **Idempotent WordPress setup.** The entrypoint downloads WordPress, writes `wp-config.php`,
  installs the site and creates the second user only if each step was not done before, so
  restarts never reinstall anything.
- **TLS.** A self-signed certificate is generated at build time; `ssl_protocols TLSv1.2 TLSv1.3`.
- **Explicit image tags.** Images are named after their service and tagged `:inception`
  (`nginx:inception`, ...), which avoids an implicit `latest` tag and any clash with the
  official Docker Hub images of the same name.

**Virtual Machines vs Docker.** A virtual machine emulates a whole computer: it boots its own
kernel and operating system on virtual hardware, which gives strong isolation but costs
gigabytes of disk, a lot of RAM and minutes to boot. A Docker container is an ordinary process
of the host, isolated with kernel namespaces and limited with cgroups; it shares the host
kernel, so it starts in about a second and its image only holds the program and its libraries.
In this project both are used: the VM is the isolated machine required by the subject, and the
services run as containers inside it.

**Secrets vs Environment Variables.** Environment variables are simple to pass to a container,
but they are part of the container configuration: anyone who can run `docker inspect` sees
them, they are inherited by every child process and they easily end up in logs. Docker secrets
are mounted as files under `/run/secrets/` (in memory), only in the services that declare them,
and they don't appear in `docker inspect`. This project uses environment variables loaded from
`srcs/.env` (the subject requires a `.env` file); that file holds credentials, so it must be
kept out of any public repository. Moving the passwords to Docker secrets is the more secure
option.

**Docker Network vs Host Network.** With `network: host` a container shares the host's network
stack: no isolation, every port it opens is open on the host, and two services can't use the
same port. This project uses a user-defined bridge network, `inception`: the containers get
their own private network, reach each other by service name through Docker's internal DNS
(`wordpress:9000`, `mariadb:3306`), and nothing is reachable from outside except the port that
is explicitly published, 443 on nginx.

**Docker Volumes vs Bind Mounts.** A bind mount maps an arbitrary host path into a container;
Docker does not manage it, and it depends on the host's directory layout. A named volume is a
Docker object (`docker volume ls`, `docker volume inspect`) with its own lifecycle and driver
options, referenced by name in the Compose file. This project uses two named volumes,
`mariadb_data` and `wordpress_data`. Their `local` driver options (`type: none`, `o: bind`,
`device: ...`) make Docker store their data in `/home/fpedroso/data/mariadb` and
`/home/fpedroso/data/wordpress` on the host, as the subject requires, while they remain named
volumes.

## Instructions

Requirements: a Linux virtual machine with Docker Engine, the Docker Compose plugin and GNU
make, plus internet access during the build (Alpine packages, WP-CLI and WordPress are
downloaded).

1. Create `srcs/.env` (see the template in [DEV_DOC.md](DEV_DOC.md)). `DATA_DIR` must be
   `/home/fpedroso/data`.
2. Make the domain point to the VM:

   ```sh
   echo "127.0.0.1 fpedroso.42.fr" | sudo tee -a /etc/hosts
   ```

3. Build and start everything:

   ```sh
   make
   ```

4. Open `https://fpedroso.42.fr` and accept the self-signed certificate warning. The
   administration panel is at `https://fpedroso.42.fr/wp-admin`.

Other Makefile targets: `make stop` / `make start` (pause and resume), `make down` (remove
the containers, keep the data), `make clean` (also remove the images), `make fclean`
(also delete the volumes and all data), `make re`, `make ps`, `make logs`.

More details: [USER_DOC.md](USER_DOC.md) for using and administering the stack,
[DEV_DOC.md](DEV_DOC.md) for setting it up and working on it.

## Resources

- Docker: [Dockerfile reference](https://docs.docker.com/reference/dockerfile/),
  [Building best practices](https://docs.docker.com/build/building/best-practices/),
  [Compose file reference](https://docs.docker.com/reference/compose-file/),
  [Control startup order in Compose](https://docs.docker.com/compose/how-tos/startup-order/),
  [Volumes](https://docs.docker.com/engine/storage/volumes/),
  [Networking](https://docs.docker.com/engine/network/),
  [Secrets in Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [Docker and the PID 1 zombie reaping problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
- NGINX: [SSL module](https://nginx.org/en/docs/http/ngx_http_ssl_module.html),
  [FastCGI module](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)
- MariaDB: [mariadb-install-db](https://mariadb.com/kb/en/mariadb-install-db/),
  [mariadbd options](https://mariadb.com/kb/en/mariadbd-options/),
  [mariadb-admin](https://mariadb.com/kb/en/mariadb-admin/)
- PHP: [FastCGI Process Manager (FPM)](https://www.php.net/manual/en/install.fpm.php)
- WordPress: [WP-CLI commands](https://developer.wordpress.org/cli/commands/)
- [Alpine Linux releases](https://alpinelinux.org/releases/)

**Use of AI.** An AI assistant (Claude) was used to:

- review the finished mandatory part against the subject and point out what could fail the
  evaluation (folder layout, Makefile location, data path, missing documentation);
- reorganize the files into `srcs/requirements/` and move the Makefile to the root;
- replace the MariaDB first-run setup (a temporary server in the background plus a wait loop)
  with `mariadbd --bootstrap`, and the WordPress wait loop with the Compose healthcheck and
  `depends_on: condition: service_healthy`;
- test the stack (TLS versions, database logins, persistence, restarts);
- draft README.md, USER_DOC.md and DEV_DOC.md.
