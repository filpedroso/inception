FROM debian:bookworm

RUN apt-get update && apt-get install nginx -y

COPY nginx.conf /etc/nginx/

COPY index.html /usr/share/nginx/html/

CMD ["nginx", "-g", "daemon off;"]
