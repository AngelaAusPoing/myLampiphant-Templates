#!/bin/sh
# Intercepts the final "exec openvpn ..." from /opt/src/run.sh.
# Never prints keys or client configs.
set -e
if [ -x /opt/mylampiphant/patch-config.sh ]; then
    /opt/mylampiphant/patch-config.sh
fi
if [ -x /opt/mylampiphant/ovpn-firewall.sh ]; then
    /opt/mylampiphant/ovpn-firewall.sh &
fi
OPENVPN=/usr/sbin/openvpn
if [ ! -x "$OPENVPN" ]; then
    OPENVPN=/usr/bin/openvpn
fi
exec "$OPENVPN" "$@"
