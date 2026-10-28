# User documentation

This guide is for whoever runs and administers the Inception stack: how to start it, use the
website and check that everything works. All commands are run from the root of the repository,
inside the virtual machine.

## What the stack provides

| Service | What it does | Reachable from |
|---|---|---|
| **nginx** | HTTPS web server, the only entry point. TLSv1.2/TLSv1.3 only. | `https://fpedroso.42.fr` (port 443) |
| **wordpress** | The WordPress website and its administration panel (PHP runs in php-fpm). | Only through nginx |
| **mariadb** | The database that stores the WordPress content and users. | Only from the wordpress container |

The website's files and the database are stored on the VM in `/home/fpedroso/data`, so they
survive restarts and rebuilds.

## Start and stop

| Command | Effect |
|---|---|
| `make` | Builds the images if needed and starts everything. The first start takes a little longer: WordPress is downloaded and installed. |
| `make stop` | Stops the containers, keeping them as they are. |
| `make start` | Starts the stopped containers again. |
| `make down` | Removes the containers and the network. The website and database data are kept. |
| `make clean` | Like `make down`, and also removes the images. Data is kept. |
| `make fclean` | **Deletes everything, including the website and the database.** The next `make` starts from a fresh install. |
| `make re` | `make fclean` followed by `make`. |

The containers restart automatically after a crash or a reboot of the VM.

## Access the website and the administration panel

Before the first visit, the VM must resolve the domain to itself (once per VM):

```sh
echo "127.0.0.1 fpedroso.42.fr" | sudo tee -a /etc/hosts
```

- Website: `https://fpedroso.42.fr`
- Administration panel: `https://fpedroso.42.fr/wp-admin` (login page: `/wp-login.php`)

The certificate is self-signed, so the browser shows a security warning the first time; accept
it to continue. Plain `http://` is not served.

## Credentials

All credentials are in `srcs/.env`. This file is private: never publish it.

| Account | Variables | Use |
|---|---|---|
| WordPress administrator | `WP_ADMIN_USER`, `WP_ADMIN_PASSWORD` | Log in to `/wp-admin` with full rights. |
| WordPress second user (author) | `WP_USER`, `WP_USER_PASSWORD` | Log in to write posts and comments. |
| Database user for WordPress | `MYSQL_USER`, `MYSQL_PASSWORD` | Used by WordPress to reach the `MYSQL_DATABASE` database. |
| Database root | `MYSQL_ROOT_PASSWORD` | Database administration, from inside the mariadb container only. |

**The accounts are created from `srcs/.env` only on the very first start.** Editing the file
afterwards does not change existing accounts. To change a password later:

- WordPress users: in the administration panel, *Users → Profile*, or from the command line:

  ```sh
  docker exec wordpress wp user update <login> --user_pass='<new password>' --allow-root
  ```

  Then update `srcs/.env` too, so it stays the reference.
- Or start over with new values: edit `srcs/.env`, then `make re`. **This deletes all content.**

## Check that everything is running

1. Container status:

   ```sh
   make ps
   ```

   The three containers `mariadb`, `wordpress` and `nginx` should be `Up`, and mariadb should
   be `(healthy)`.
2. The website answers over HTTPS:

   ```sh
   curl -kI https://fpedroso.42.fr
   ```

   Expected: `HTTP/1.1 200 OK`.
3. Logs, if something looks wrong (`Ctrl+C` to quit):

   ```sh
   make logs
   ```

4. The database is up and holds the WordPress tables (the password is asked interactively):

   ```sh
   docker exec -it mariadb mariadb -u root -p -e "SHOW TABLES" wordpress
   ```

5. The WordPress users exist:

   ```sh
   docker exec wordpress wp user list --allow-root
   ```

If the website shows *Error establishing a database connection* right after a start, wait a
few seconds: the database may still be starting. If it persists, check `make logs`.
