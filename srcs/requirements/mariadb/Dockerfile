FROM alpine:3.23

RUN apk add --no-cache mariadb mariadb-client

# Substitui o config padrão do Alpine (que vem com skip-networking)
COPY conf/mariadb-server.cnf /etc/my.cnf.d/mariadb-server.cnf

COPY tools/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 3306

ENTRYPOINT ["/entrypoint.sh"]
