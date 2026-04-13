#!/bin/sh
set -e

php artisan config:cache
php artisan route:cache
php artisan view:cache

if [ "$RUN_MIGRATIONS" = "true" ]; then
  php artisan migrate --force --no-interaction
fi

exec "$@"
