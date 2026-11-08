#!/bin/sh
set -e

WP_PATH=/var/www/html

# Não há espera pelo banco aqui: o compose só sobe este container depois que o
# healthcheck do MariaDB passa (depends_on: condition: service_healthy).
# Se o banco ainda assim não responder (ex.: reboot, em que o Docker religa os
# containers sem ordem), um comando wp falha, o set -e encerra o script e o
# restart: always tenta de novo.

# As portas vêm do .env. O que a instalação grava nos volumes (DB_HOST no
# wp-config.php, URL do site no banco) é ressincronizado a cada start (passos 3
# e 5), então uma troca de porta vale depois de um simples make.
DB_HOST="mariadb:${MYSQL_PORT:-3306}"
SITE_URL="https://$DOMAIN_NAME"
if [ "${NGINX_PORT:-443}" != "443" ]; then
    SITE_URL="$SITE_URL:$NGINX_PORT"
fi

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
        --dbpass="$MYSQL_PASSWORD" --dbhost="$DB_HOST"
fi

# 3. Endereço do banco sempre igual ao .env (o wp-config.php fica no volume)
wp config set DB_HOST "$DB_HOST" --path="$WP_PATH" --allow-root

# 4. Instalação do site (e criação das tabelas no banco)
if ! wp core is-installed --path="$WP_PATH" --allow-root; then
    echo "[wordpress] installing site"
    wp core install --path="$WP_PATH" --allow-root --skip-email \
        --url="$SITE_URL" --title="$WP_TITLE" \
        --admin_user="$WP_ADMIN_USER" --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL"
fi

# 5. URL do site sempre igual ao .env (fica gravada no banco; com a porta errada,
# o WordPress redireciona o navegador para ela)
wp option update home "$SITE_URL" --path="$WP_PATH" --allow-root
wp option update siteurl "$SITE_URL" --path="$WP_PATH" --allow-root

# 6. Segundo usuário (só se ainda não existe)
if ! wp user get "$WP_USER" --path="$WP_PATH" --allow-root >/dev/null 2>&1; then
    echo "[wordpress] creating second user"
    wp user create "$WP_USER" "$WP_USER_EMAIL" --user_pass="$WP_USER_PASSWORD" \
        --role=author --path="$WP_PATH" --allow-root
fi

# 7. Entrega os arquivos ao usuário com que os workers do php-fpm rodam
chown -R nobody:nobody "$WP_PATH"

# 8. php-fpm em primeiro plano; o exec o torna o PID 1
exec php-fpm83 -F
