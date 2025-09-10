# nginx.conf
cat > "${NGX_DIR}/nginx.conf" <<'NGINX'
server {
    listen 80 default_server;
    server_name _;
    root /var/www/html/public;
    index index.php index.html;
    location / { try_files $uri $uri/ /index.php?$query_string; }
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_pass php:9000;
        fastcgi_intercept_errors on;
        fastcgi_param HTTP_X_FORWARDED_PROTO $http_x_forwarded_proto;
        fastcgi_param HTTP_X_FORWARDED_HOST  $http_x_forwarded_host;
        fastcgi_param HTTP_X_FORWARDED_PORT  $http_x_forwarded_port;
        fastcgi_param HTTP_X_FORWARDED_FOR   $proxy_add_x_forwarded_for;
        fastcgi_param HTTPS                  on;
        fastcgi_param SERVER_PORT            443;
    }
    location ~ /\.(?!well-known).* { deny all; }
    client_max_body_size 32M;
}
NGINX

# Dockerfiles parametrizados (templates .tpl)
cat > "${PHP_SQLITE_DF}.min.tpl" <<'DOCKER'
FROM __PHP_BASE__
RUN set -eux; \
    apk add --no-cache oniguruma sqlite-libs freetype-dev libjpeg-turbo-dev libpng-dev libzip-dev; \
    apk add --no-cache --virtual .build-deps $PHPIZE_DEPS oniguruma-dev sqlite-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" mbstring bcmath pdo_sqlite gd zip exif; \
    apk del --no-network .build-deps
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /var/www/html
DOCKER

cat > "${PHP_SQLITE_DF}.full.tpl" <<'DOCKER'
FROM __PHP_BASE__
RUN set -eux; \
    apk add --no-cache oniguruma sqlite-libs icu-libs freetype-dev libjpeg-turbo-dev libpng-dev libzip-dev; \
    apk add --no-cache --virtual .build-deps $PHPIZE_DEPS oniguruma-dev sqlite-dev icu-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" mbstring bcmath pdo_sqlite gd zip exif intl; \
    apk del --no-network .build-deps
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /var/www/html
DOCKER

sed -i "s|__PHP_BASE__|php:${PHP_VER}-fpm-alpine|g" "${PHP_SQLITE_DF}.min.tpl" "${PHP_SQLITE_DF}.full.tpl"

cat > "${PHP_MYSQL_DF}.min.tpl" <<'DOCKER'
FROM __PHP_BASE__
RUN set -eux; \
    apk add --no-cache oniguruma sqlite-libs freetype-dev libjpeg-turbo-dev libpng-dev libzip-dev; \
    apk add --no-cache --virtual .build-deps $PHPIZE_DEPS oniguruma-dev sqlite-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" pdo_mysql pdo_sqlite mbstring bcmath gd zip exif; \
    apk del --no-network .build-deps
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /var/www/html
DOCKER

cat > "${PHP_MYSQL_DF}.full.tpl" <<'DOCKER'
FROM __PHP_BASE__
RUN set -eux; \
    apk add --no-cache oniguruma sqlite-libs icu-libs freetype-dev libjpeg-turbo-dev libpng-dev libzip-dev; \
    apk add --no-cache --virtual .build-deps $PHPIZE_DEPS oniguruma-dev sqlite-dev icu-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" pdo_mysql pdo_sqlite mbstring bcmath gd zip exif intl; \
    apk del --no-network .build-deps
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /var/www/html
DOCKER

sed -i "s|__PHP_BASE__|php:${PHP_VER}-fpm-alpine|g" "${PHP_MYSQL_DF}.min.tpl" "${PHP_MYSQL_DF}.full.tpl"

save_state
