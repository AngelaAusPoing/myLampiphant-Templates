#!/bin/sh
# Wrapper around the official wg-easy entrypoint. Starts the isolation
# firewall enforcer, then hands off to docker-entrypoint.sh + image CMD.
set -e
if [ -x /opt/mylampiphant/wg-firewall.sh ]; then
    /opt/mylampiphant/wg-firewall.sh &
fi
if [ "$#" -eq 0 ]; then
    set -- /usr/bin/dumb-init node server/index.mjs
fi
exec docker-entrypoint.sh "$@"
