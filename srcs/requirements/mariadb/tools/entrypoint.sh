#!/bin/sh
# se der erro, pára tudo
set -e

# onde o mariadb guarda os bancos
DATADIR=/var/lib/mysql

# cria a pasta do socket (o servidor final escuta nele, além da porta 3306)
mkdir -p /run/mysqld

# dá a posse dessas 2 pastas ao user mysql
chown -R mysql:mysql /run/mysqld "$DATADIR"

# Só inicializa se o volume ainda não tem o banco de sistema do MariaDB
if [ ! -d "$DATADIR/mysql" ]; then
    echo "[mariadb] first run: initializing data directory"
	# cria os arquivos iniciais do banco de sistema, e a conta root.
	# --skip-test-db: sem o banco "test" e sem os usuários anônimos (''@'localhost'),
	# que vêm junto com ele e "roubariam" os logins locais de usuários com host '%'
    mariadb-install-db --user=mysql --datadir="$DATADIR" --skip-test-db > /dev/null

	# --bootstrap: o mariadbd lê o SQL do stdin, executa e sai sozinho.
	# Sem rede, sem socket, sem servidor em background para esperar ou matar.
	# Nesse modo as tabelas de permissão não vêm carregadas: o FLUSH PRIVILEGES
	# do começo carrega, senão ALTER USER, CREATE USER e GRANT falham.
    mariadbd --user=mysql --bootstrap <<EOSQL
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL
    echo "[mariadb] initialization done"
fi

# executa o servidor, agora com rede e todas as configs do .cnf
# familia exec substitui toda a imagem do processo. mariadb "se torna" o PID 1
exec mariadbd --user=mysql
