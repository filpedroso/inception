COMPOSE_FILE := srcs/docker-compose.yml
ENV_FILE     := srcs/.env
COMPOSE      := docker compose -f $(COMPOSE_FILE)
CLEANER      := alpine:3.23

# DATA_DIR is read from srcs/.env (the value must have no quotes there)
DATA_DIR := $(shell grep '^DATA_DIR=' $(ENV_FILE) 2>/dev/null | tail -n1 | cut -d= -f2-)

all: up

up: $(ENV_FILE) dirs
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

# containers, network and the images built here (volumes and data are kept)
clean:
	$(COMPOSE) down --rmi all

# everything: also the volumes and the contents of the data folders
fclean: dirs
	$(COMPOSE) down -v --rmi all
	docker run --rm -v "$(DATA_DIR)":/data $(CLEANER) \
		find /data/mariadb /data/wordpress -mindepth 1 -delete

re:
	@$(MAKE) --no-print-directory fclean
	@$(MAKE) --no-print-directory all

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

# the bind-backed volumes need these folders to exist before "up"
dirs: check-data-dir
	@mkdir -p "$(DATA_DIR)/mariadb" "$(DATA_DIR)/wordpress"

check-data-dir:
	@[ -n "$(DATA_DIR)" ] && [ "$(DATA_DIR)" != "/" ] || { echo "DATA_DIR must be set in $(ENV_FILE) and must not be /"; exit 1; }

$(ENV_FILE):
	@echo "Missing $(ENV_FILE)"; exit 1

.PHONY: all up down stop start clean fclean re logs ps dirs check-data-dir
