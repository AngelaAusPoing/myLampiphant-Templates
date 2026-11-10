#!/bin/sh
# Internal loop: run imapfilter, then sleep (default 15 minutes).
# Never prints secret values.
set -eu
CONFIG="${IMAPFILTER_CONFIG:-/config/config.lua}"
SLEEP="${IMAPFILTER_SLEEP:-900}"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: imapfilter config not found: $CONFIG" >&2
    exit 1
fi

echo "imapfilter loop starting (sleep=${SLEEP}s, TEST=${IMAPFILTER_TEST:-true}, config=$CONFIG)"
while true; do
    echo "$(date -Iseconds 2>/dev/null || date) starting imapfilter run"
    imapfilter -c "$CONFIG" || echo "imapfilter exited with status $?"
    echo "$(date -Iseconds 2>/dev/null || date) sleeping ${SLEEP}s"
    sleep "$SLEEP"
done
