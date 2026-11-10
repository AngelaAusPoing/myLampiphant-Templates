#!/bin/sh
# Re-apply isolation rules so WireGuard clients can reach only this
# customer's Docker network (and the VPN subnet itself). Everything else,
# including other RFC1918 ranges and the public internet via the tunnel,
# is dropped. Split-tunnel is the default (AllowedIPs); this is the
# server-side backstop.
#
# firewall.conf is written by install.sh (WG_CIDR, CUSTOMER_CIDR, WG_IF).
# This script is idempotent and loops so rules survive wg-easy rewrites.
set -eu

CONF=/opt/mylampiphant/firewall.conf
CHAIN=WG_ISOLATION

if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF"
fi

WG_IF="${WG_IF:-wg0}"
WG_CIDR="${WG_CIDR:-}"
CUSTOMER_CIDR="${CUSTOMER_CIDR:-}"

apply_rules() {
    if [ -z "$WG_CIDR" ] || [ -z "$CUSTOMER_CIDR" ]; then
        return 0
    fi
    if ! ip link show "$WG_IF" >/dev/null 2>&1; then
        return 0
    fi
    if ! command -v iptables >/dev/null 2>&1; then
        return 0
    fi

    iptables -N "$CHAIN" 2>/dev/null || true
    iptables -F "$CHAIN"

    iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A "$CHAIN" -s "$WG_CIDR" -d "$CUSTOMER_CIDR" -j ACCEPT
    iptables -A "$CHAIN" -s "$CUSTOMER_CIDR" -d "$WG_CIDR" -j ACCEPT
    iptables -A "$CHAIN" -s "$WG_CIDR" -d "$WG_CIDR" -j ACCEPT
    # Default: no path into other private nets or out to the internet
    iptables -A "$CHAIN" -s "$WG_CIDR" -j DROP
    iptables -A "$CHAIN" -d "$WG_CIDR" -j DROP

    # Keep our chain first on FORWARD so it wins over looser MASQUERADE/ACCEPT
    iptables -C FORWARD -j "$CHAIN" 2>/dev/null || iptables -I FORWARD 1 -j "$CHAIN"
}

while true; do
    apply_rules || true
    sleep 15
done
