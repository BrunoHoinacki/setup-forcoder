version: "3.8"

services:
  nginx:
    image: nginx:alpine
    volumes:
      - ${APP_DIR}:/var/www/html:rw
      - ${APP_DIR}/.deploy/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - edge
    deploy:
      labels:
        - traefik.enable=true
        - traefik.http.routers.${APP_NAME}.rule=Host(`${APP_DOMAIN}`)
        - traefik.http.routers.${APP_NAME}.entrypoints=websecure
        - traefik.http.routers.${APP_NAME}.tls.certresolver=cf
        - traefik.http.services.${APP_NAME}.loadbalancer.server.port=80

  php:
    image: php:8.4-fpm
    working_dir: /var/www/html
    volumes:
      - ${APP_DIR}:/var/www/html:rw
    networks:
      - edge
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: app
      MYSQL_USER: app
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ${APP_NAME}_db:/var/lib/mysql
    networks:
      - edge
    deploy:
      placement:
        constraints:
          - node.role == manager

networks:
  edge:
    external: true
    name: ${EDGE}

volumes:
  ${APP_NAME}_db:
