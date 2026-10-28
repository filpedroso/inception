# Developer documentation

How to set up the project from scratch, build and run it, manage its containers and volumes,
and where its data lives.

## Repository layout

```
.
├── Makefile                      # entry point: wraps docker compose
└── srcs/
    ├── .env                      # configuration + credentials (private, not versioned)
    ├── docker-compose.yml        # services, network, volumes, healthcheck
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/mariadb-server.cnf   # replaces Alpine's default (which disables networking)
        │   └── tools/entrypoint.sh       # first-run setup, then exec mariadbd
        ├── nginx/
        │   ├── Dockerfile                # also generates the self-signed certificate
        │   └── conf/nginx.conf           # 443 only, TLSv1.2/1.3, FastCGI to wordpress:9000
        └── wordpress/
            ├── Dockerfile                # PHP 8.3 + php-fpm + WP-CLI
            ├── conf/www.conf             # php-fpm pool, listens on 0.0.0.0:9000
            └── tools/entrypoint.sh       # installs WordPress with WP-CLI, then exec php-fpm
```

## Set up the environment from scratch

### Prerequisites

- A Linux virtual machine (Debian or Ubuntu, for example).
- Docker Engine with the Compose plugin (`docker compose version` must work), and your user
  in the `docker` group (or use `sudo`).
- GNU make and git.
- Internet access during the build: Alpine packages, WP-CLI and WordPress are downloaded.

### Configuration file: `srcs/.env`

The project reads all of its configuration from `srcs/.env`. The file holds credentials, so it
is not versioned: create it after cloning. Values are written without quotes.

```sh
DATA_DIR=/home/fpedroso/data
DOMAIN_NAME=fpedroso.42.fr

MYSQL_ROOT_PASSWORD=<choose one>
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MYSQL_PASSWORD=<choose one>

WP_TITLE=Inception
WP_ADMIN_USER=<must not contain "admin" or "Admin">
WP_ADMIN_PASSWORD=<choose one>
WP_ADMIN_EMAIL=<email>
WP_USER=<second user login>
WP_USER_PASSWORD=<choose one>
WP_USER_EMAIL=<email, different from the admin's>
```

| Variable | Used by | Meaning |
|---|---|---|
| `DATA_DIR` | Makefile, Compose | Host folder that holds the volumes' data. Must be `/home/<login>/data`. |
| `DOMAIN_NAME` | wordpress | Site URL, `https://$DOMAIN_NAME`. |
| `MYSQL_ROOT_PASSWORD` | mariadb | Password set for `root@localhost`. |
| `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` | mariadb, wordpress | The WordPress database and the account (`'user'@'%'`) that has all rights on it. |
| `WP_*` | wordpress | Site title and the two WordPress users (administrator and author). |

These values are applied only on the first start, when the volumes are empty. To apply
changed values, reset the data with `make re`.

### Domain

The domain must point to the VM itself:

```sh
echo "127.0.0.1 fpedroso.42.fr" | sudo tee -a /etc/hosts
```

The domain also appears in `srcs/requirements/nginx/conf/nginx.conf` (`server_name`) and in
`srcs/requirements/nginx/Dockerfile` (certificate CN). Update both if the login changes.

## Build and launch

```sh
make
```

`make` checks that `srcs/.env` exists and that `DATA_DIR` is set, creates
`$DATA_DIR/mariadb` and `$DATA_DIR/wordpress` (the volumes need them to exist), then runs
`docker compose -f srcs/docker-compose.yml up -d --build`.

Startup sequence:

1. **mariadb** starts. If its volume is empty, the entrypoint runs `mariadb-install-db
   --skip-test-db`, then `mariadbd --bootstrap` with the setup SQL (root password, database,
   WordPress user). Then it `exec`s the real `mariadbd`.
2. Compose waits until the mariadb healthcheck (`mariadb-admin ping`) passes, because
   wordpress declares `depends_on: mariadb: condition: service_healthy`.
3. **wordpress** starts. Each step runs only if it was not done before: download WordPress,
   create `wp-config.php`, install the site, create the second user. Then it `exec`s
   `php-fpm83 -F`.
4. **nginx** starts and serves `https://$DOMAIN_NAME`.

| Target | Command behind it |
|---|---|
| `make` / `make up` | `docker compose up -d --build` |
| `make stop` / `make start` | `docker compose stop` / `start` |
| `make down` | `docker compose down` (containers and network) |
| `make clean` | `docker compose down --rmi all` (also the images) |
| `make fclean` | `docker compose down -v --rmi all`, then empties `$DATA_DIR/mariadb` and `$DATA_DIR/wordpress` |
| `make re` | `make fclean` then `make` |
| `make ps` / `make logs` | `docker compose ps` / `logs -f` |

## Manage containers and volumes

Docker Compose commands take the Compose file as an argument when run from the repository root:

```sh
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs -f wordpress      # one service's logs
docker compose -f srcs/docker-compose.yml up -d --build nginx    # rebuild and restart one service
docker compose -f srcs/docker-compose.yml restart mariadb
```

Inside the containers:

```sh
docker exec -it wordpress sh                      # shell in a container
docker exec wordpress wp user list --allow-root   # WP-CLI
docker exec -it mariadb mariadb -u root -p        # SQL console as root
docker inspect mariadb --format '{{json .State.Health}}'   # healthcheck results
```

Images, network and volumes:

```sh
docker images | grep inception        # mariadb:inception, wordpress:inception, nginx:inception
docker network inspect inception
docker volume ls                      # mariadb_data, wordpress_data
docker volume inspect wordpress_data  # Options.device shows the host folder
```

## Where the data is stored and how it persists

| Volume | Mounted at | Host folder |
|---|---|---|
| `mariadb_data` | `/var/lib/mysql` in mariadb | `$DATA_DIR/mariadb` |
| `wordpress_data` | `/var/www/html` in wordpress (read-only in nginx) | `$DATA_DIR/wordpress` |

Both are Docker named volumes created by Compose with the `local` driver and the options
`type: none`, `o: bind`, `device: $DATA_DIR/...`, which makes Docker keep their data in those
host folders.

- The data survives `make stop`, `make down`, `make clean`, image rebuilds and VM reboots.
- `make fclean` (and `make re`) removes the volumes and empties the folders. It empties them
  through a short-lived `alpine` container because the database files belong to the
  container's `mysql` user, which the host user cannot delete without `sudo`.
- `docker volume rm` alone does **not** delete the files in `$DATA_DIR`. The entrypoints see
  the existing data and skip the first-run setup.

## Troubleshooting

- **`exec /entrypoint.sh: no such file or directory`**: the scripts have Windows line endings
  (CRLF). Clone the repository on the VM instead of copying it from Windows, or convert the
  files to LF.
- **`dependency failed to start: container mariadb is unhealthy`**: see
  `docker logs mariadb`. If a first-run setup was interrupted, reset with `make re`.
- **Changes to `srcs/.env` have no effect**: the accounts were created on the first run, from
  the old values. Change them from inside (see [USER_DOC.md](USER_DOC.md#credentials)) or
  start from scratch with `make re`, which deletes all content.
