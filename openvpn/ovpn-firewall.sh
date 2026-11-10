#!/bin/sh
# Re-apply isolation rules so OpenVPN clients can reach only this
# customer's Docker network (and the VPN subnet itself). Everything else,
# including other RFC1918 ranges and the public internet via the tunnel,
# is dropped. Split-tunnel is the default (pushed routes); this is the
# server-side backstop.
#
# Also removes the image's default MASQUERADE/FORWARD ACCEPT for
# 10.8.0.0/24, which would otherwise leak after run.sh starts.
#
# firewall.conf is written by install.sh (OVPN_CIDR, CUSTOMER_CIDR, OVPN_IF).
# This script is idempotent and loops so rules survive image iptables setup.
set -eu

CONF=/opt/mylampiphant/firewall.conf
CHAIN=OVPN_ISOLATION

if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF"
fi

OVPN_IF="${OVPN_IF:-tun0}"
OVPN_CIDR="${OVPN_CIDR:-}"
CUSTOMER_CIDR="${CUSTOMER_CIDR:-}"

net_iface() {
    ip -4 route list 0/0 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

delete_image_default_rules() {
    # The image always tries to NAT 10.8.0.0/24. Drop those leftover rules.
    # Also drop a blanket FORWARD ACCEPT / NAT for our own CIDR if present;
    # isolation + a targeted MASQUERADE replace them.
    local iface
    iface="$(net_iface)"
    if [ -n "$iface" ]; then
        iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o "$iface" -j MASQUERADE 2>/dev/null             && iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o "$iface" -j MASQUERADE || true
        if [ -n "$OVPN_CIDR" ]; then
            iptables -t nat -C POSTROUTING -s "$OVPN_CIDR" -o "$iface" -j MASQUERADE 2>/dev/null                 && iptables -t nat -D POSTROUTING -s "$OVPN_CIDR" -o "$iface" -j MASQUERADE || true
        fi
    fi
    iptables -C FORWARD -s 10.8.0.0/24 -j ACCEPT 2>/dev/null         && iptables -D FORWARD -s 10.8.0.0/24 -j ACCEPT || true
    if [ -n "$OVPN_CIDR" ]; then
        iptables -C FORWARD -s "$OVPN_CIDR" -j ACCEPT 2>/dev/null             && iptables -D FORWARD -s "$OVPN_CIDR" -j ACCEPT || true
    fi
}

apply_rules() {
    if [ -z "$OVPN_CIDR" ] || [ -z "$CUSTOMER_CIDR" ]; then
        return 0
    fi
    if ! command -v iptables >/dev/null 2>&1; then
        return 0
    fi

    delete_image_default_rules || true

    if ! ip link show "$OVPN_IF" >/dev/null 2>&1; then
        return 0
    fi

    iptables -N "$CHAIN" 2>/dev/null || true
    iptables -F "$CHAIN"

    iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null         || iptables -A "$CHAIN" -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A "$CHAIN" -s "$OVPN_CIDR" -d "$CUSTOMER_CIDR" -j ACCEPT
    iptables -A "$CHAIN" -s "$CUSTOMER_CIDR" -d "$OVPN_CIDR" -j ACCEPT
    iptables -A "$CHAIN" -s "$OVPN_CIDR" -d "$OVPN_CIDR" -j ACCEPT
    # Default: no path into other private nets or out to the internet
    iptables -A "$CHAIN" -s "$OVPN_CIDR" -j DROP
    iptables -A "$CHAIN" -d "$OVPN_CIDR" -j DROP

    iptables -C FORWARD -j "$CHAIN" 2>/dev/null || iptables -I FORWARD 1 -j "$CHAIN"

    # NAT only towards this customer's Docker network so those containers
    # can reply without a return route to the VPN subnet.
    iptables -t nat -C POSTROUTING -s "$OVPN_CIDR" -d "$CUSTOMER_CIDR" -j MASQUERADE 2>/dev/null         || iptables -t nat -A POSTROUTING -s "$OVPN_CIDR" -d "$CUSTOMER_CIDR" -j MASQUERADE
}

while true; do
    apply_rules || true
    sleep 15
done
