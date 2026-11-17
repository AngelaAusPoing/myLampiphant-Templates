#!/bin/sh
# Pollaris container entrypoint: warm the Symfony cache, run DB migrations
# (web container only, POLLARIS_RUN_MIGRATIONS=true), then exec the command.
# Never prints secrets.
set -eu
cd /app

php bin/console cache:clear --no-warmup --no-interaction >/dev/null
php bin/console cache:warmup --no-interaction >/dev/null

if [ "${POLLARIS_RUN_MIGRATIONS:-false}" = "true" ]; then
    i=0
    until php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration; do
        i=$((i + 1))
        if [ "$i" -ge 10 ]; then
            echo "Pollaris: database migrations failed" >&2
            exit 1
        fi
        echo "Pollaris: database not ready yet, retrying in 5s ..." >&2
        sleep 5
    done
fi

chown -R www-data:www-data /app/var 2>/dev/null || true
exec "$@"
