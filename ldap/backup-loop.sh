#!/bin/bash
# Daily (or BACKUP_INTERVAL) LDIF export of the directory. No passwords on the command line.
set -euo pipefail

URI="${LDAP_SERVER_URI:-ldap://ldap:389}"
BASE="${LDAP_BASE_DN:?LDAP_BASE_DN is required}"
BIND_DN="${LDAP_ROOT_DN:?LDAP_ROOT_DN is required}"
PWFILE="${LDAP_ROOT_PW_FILE:-/run/secrets/ldap_root_pw}"
INTERVAL="${LDAP_BACKUP_INTERVAL:-86400}"
DEST="${LDAP_BACKUP_DIR:-/backup}"
KEEP="${LDAP_BACKUP_KEEP:-14}"

mkdir -p "$DEST"
# Wait until slapd answers (up to 2 minutes)
for _ in $(seq 1 24); do
    if ldapsearch -x -H "$URI" -s base -b "" namingContexts >/dev/null 2>&1; then
        break
    fi
    sleep 5
done

echo "ldap backup loop started (interval ${INTERVAL}s, keep ${KEEP} files)"

while true; do
    ts=$(date +%Y%m%d_%H%M%S)
    tmp="${DEST}/ldap-${ts}.ldif.tmp"
    out="${DEST}/ldap-${ts}.ldif"
    if ldapsearch -x -H "$URI" -D "$BIND_DN" -y "$PWFILE" -b "$BASE" -LLL -E pr=1000/noprompt >"$tmp" 2>/tmp/ldap-backup.err; then
        mv "$tmp" "$out"
        chmod 600 "$out"
        echo "exported ${out}"
        # prune old exports
        ls -1t "${DEST}"/ldap-*.ldif 2>/dev/null | tail -n +"$((KEEP + 1))" | xargs -r rm -f
    else
        echo "backup failed, see /tmp/ldap-backup.err" >&2
        rm -f "$tmp"
    fi
    sleep "$INTERVAL"
done
