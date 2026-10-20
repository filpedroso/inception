FROM alpine:3.23

RUN apk add --no-cache \
	php83				`# php CLI interpreter`			\
	php83-fpm			`# PHP-FPM fastcgi manager`		\
	php83-mysqli		`# MySQL driver for mariaDB`	\
	php83-phar			`# Phar archive support`		\
	php83-curl			`# Curl for php`				\
	php83-mbstring		`# Multi-byte string utils`		\
	php83-xml			`# XML parsing support`			\
	php83-dom			`# DOM support`					\
	php83-openssl		`# OpenSSL encryption`			\
	php83-iconv			`# Character conversion`		\
	php83-session		`# Session handling`			\
	php83-ctype			`# Character type checking`		\
	php83-zip			`# Zip archive extension`		\
	php83-gd			`# GD graphics library`			\
	php83-intl			`# Internationalization`		\
	php83-opcache		`# PHP bytecode caching`		\
	mariadb-client		`# MariaDB database client`		\
	curl

# Symlink php from actual php83 (wp-cli searches for php)
RUN ln -s /usr/bin/php83 /usr/bin/php

RUN curl -fsSL -o /usr/local/bin/wp												\
	https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar	\
	&& chmod +x /usr/local/bin/wp

WORKDIR /var/www/html

COPY www.conf	/etc/php83/php-fpm.d/www.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["/entrypoint.sh"]
