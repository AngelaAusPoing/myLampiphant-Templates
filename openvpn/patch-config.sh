#!/bin/sh
# After the image has generated (or loaded) /etc/openvpn/server/server.conf,
# apply the myLampiphant subnet and split-tunnel routes. Idempotent.
# Never prints certificates, keys or client profiles.
set -eu

CONF=/etc/openvpn/server/server.conf
FIREWALL=/opt/mylampiphant/firewall.conf

if [ ! -f "$CONF" ]; then
    echo "patch-config: server.conf not present yet, skipping."
    exit 0
fi

OVPN_NET="10.8.0.0"
OVPN_MASK="255.255.255.0"
CUSTOMER_NET=""
CUSTOMER_MASK=""
OVPN_PORT=""
OVPN_PROTO=""

if [ -f "$FIREWALL" ]; then
    # shellcheck disable=SC1090
    . "$FIREWALL"
fi

OVPN_NET="${OVPN_NET:-10.8.0.0}"
OVPN_MASK="${OVPN_MASK:-255.255.255.0}"

tmp="$(mktemp)"
# Drop full-tunnel pushes and any previous myLampiphant route/marker lines;
# they are rewritten below.
grep -v -E '^push "redirect-gateway|^# myLampiphant:|^push "route ' "$CONF" > "$tmp" || true

# Replace the VPN subnet (image default is 10.8.0.0/24).
if grep -qE '^server ' "$tmp"; then
    sed -i "s/^server .*/server ${OVPN_NET} ${OVPN_MASK}/" "$tmp"
else
    printf 'server %s %s\n' "$OVPN_NET" "$OVPN_MASK" >> "$tmp"
fi

if [ -n "${OVPN_PORT:-}" ]; then
    if grep -qE '^port ' "$tmp"; then
        sed -i "s/^port .*/port ${OVPN_PORT}/" "$tmp"
    fi
fi
if [ -n "${OVPN_PROTO:-}" ]; then
    if grep -qE '^proto ' "$tmp"; then
        sed -i "s/^proto .*/proto ${OVPN_PROTO}/" "$tmp"
    fi
fi

{
    echo "# myLampiphant: split-tunnel and custom subnet (patched, do not add redirect-gateway)"
    if [ -n "${CUSTOMER_NET:-}" ] && [ -n "${CUSTOMER_MASK:-}" ]; then
        printf 'push "route %s %s"\n' "$CUSTOMER_NET" "$CUSTOMER_MASK"
    fi
    if [ -n "${OVPN_NET:-}" ] && [ -n "${OVPN_MASK:-}" ]; then
        printf 'push "route %s %s"\n' "$OVPN_NET" "$OVPN_MASK"
    fi
} >> "$tmp"

cat "$tmp" > "$CONF"
rm -f "$tmp"
echo "patch-config: applied subnet ${OVPN_NET}/${OVPN_MASK} and split-tunnel routes."
