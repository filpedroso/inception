#!/bin/sh
set -e

WP_PATH=/var/www/html

# Não há espera pelo banco aqui: o compose só sobe este container depois que o
# healthcheck do MariaDB passa (depends_on: condition: service_healthy).
# Se o banco ainda assim não responder (ex.: reboot, em que o Docker religa os
# containers sem ordem), um comando wp falha, o set -e encerra o script e o
# restart: always tenta de novo.

# 1. Arquivos do WordPress (só se o volume ainda não os tem)
if [ ! -f "$WP_PATH/wp-load.php" ]; then
    echo "[wordpress] downloading WordPress"
    wp core download --path="$WP_PATH" --allow-root
fi

# 2. wp-config.php (credenciais do banco)
if [ ! -f "$WP_PATH/wp-config.php" ]; then
    echo "[wordpress] creating wp-config.php"
    wp config create --path="$WP_PATH" --allow-root \
        --dbname="$MYSQL_DATABASE" --dbuser="$MYSQL_USER" \
        --dbpass="$MYSQL_PASSWORD" --dbhost=mariadb
fi

# 3. Instalação do site (e criação das tabelas no banco)
if ! wp core is-installed --path="$WP_PATH" --allow-root; then
    echo "[wordpress] installing site"
    wp core install --path="$WP_PATH" --allow-root --skip-email \
        --url="https://$DOMAIN_NAME" --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN_USER" --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL"
fi

# 4. Segundo usuário (só se ainda não existe)
if ! wp user get "$WP_USER" --path="$WP_PATH" --allow-root >/dev/null 2>&1; then
    echo "[wordpress] creating second user"
    wp user create "$WP_USER" "$WP_USER_EMAIL" --user_pass="$WP_USER_PASSWORD" \
        --role=author --path="$WP_PATH" --allow-root
fi

# 5. Entrega os arquivos ao usuário com que os workers do php-fpm rodam
chown -R nobody:nobody "$WP_PATH"

# 6. php-fpm em primeiro plano; o exec o torna o PID 1
exec php-fpm83 -F
