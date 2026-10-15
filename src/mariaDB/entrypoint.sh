#!/bin/sh
# se der erro, pára tudo
set -e

# onde o mariadb guarda os bancos
DATADIR=/var/lib/mysql

# socket que vai ser criado para comm do servidor temp
SOCKET=/run/mysqld/mysqld.sock

# cria a pasta do socket
mkdir -p /run/mysqld

# dá a posse dessas 2 pastas ao user mysql
chown -R mysql:mysql /run/mysqld "$DATADIR"

# Só inicializa se o volume ainda não tem o banco de sistema do MariaDB
if [ ! -d "$DATADIR/mysql" ]; then
    echo "[mariadb] first run: initializing data directory"
	# cria os arquivos iniciais do banco de sistema, e a conta root
    mariadb-install-db --user=mysql --datadir="$DATADIR" --skip-test-db > /dev/null

    # Sobe o servidor: sem rede, apenas socket
    mariadbd --user=mysql --skip-networking --socket="$SOCKET" &
    pid="$!"

	# pinga o servidor, até ele estar de pé.
	# mariadb-admin usa client administrativo (sem SQL: ping, shutdown, status)
    until mariadb-admin --socket="$SOCKET" ping --silent; do
        sleep 1
    done

	# usa um client para mandar SQL via socket pro servidor
    mariadb --socket="$SOCKET" <<EOSQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL

	# mata o servidor temporário
    mariadb-admin --socket="$SOCKET" -uroot -p"${MYSQL_ROOT_PASSWORD}" shutdown
    wait "$pid"
    echo "[mariadb] initialization done"
fi

# executa o servidor, agora com rede e todas as configs do .cnf
# familia exec substitui toda a imagem do processo. mariadb "se torna" o PID 1
exec mariadbd --user=mysql
