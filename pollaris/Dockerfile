# Pollaris image (successor of Framadate / OpenSondage), built by Komodo from this
# build context. Upstream ships no production image, so we build one from the
# tagged release on framagit. No secrets are baked into the image.
#
# Runtime: FrankenPHP (Caddy + PHP in one process, official multi-arch image incl. arm64).
ARG FRANKENPHP_IMAGE=dunglas/frankenphp:1.13.5-php8.4.27-alpine
ARG COMPOSER_IMAGE=composer:2.11.2

FROM ${COMPOSER_IMAGE} AS composer

FROM ${FRANKENPHP_IMAGE}
ARG POLLARIS_VERSION=1.2.3
ARG POLLARIS_REPO=https://framagit.org/pollaris/pollaris.git

ENV APP_ENV=prod \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/tmp/composer \
    SERVER_NAME=:80

RUN apk add --no-cache git \
 && install-php-extensions intl pdo_pgsql zip pcntl opcache

COPY --from=composer /usr/bin/composer /usr/bin/composer

WORKDIR /app
RUN rm -rf /app/* \
 && git clone --depth 1 --branch "${POLLARIS_VERSION}" "${POLLARIS_REPO}" /app \
 && rm -rf /app/.git \
 && composer install --no-dev --optimize-autoloader --no-interaction --no-progress --no-scripts \
 && rm -rf /tmp/composer \
 && mkdir -p /app/var \
 && chown -R www-data:www-data /app/var

COPY pollaris-entrypoint.sh /usr/local/bin/pollaris-entrypoint.sh
RUN chmod 755 /usr/local/bin/pollaris-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/pollaris-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]
