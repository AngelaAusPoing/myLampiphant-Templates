#!/bin/bash
# Rebuild custom-jvb.conf from drop-ins, then hand off to the official s6 init.
set -euo pipefail

export JITSI_JVB_CONFIG_DIR="${JITSI_JVB_CONFIG_DIR:-/config}"
export JITSI_XMPP_SERVERS_DIR="${JITSI_XMPP_SERVERS_DIR:-/xmpp-servers}"

if [ -x /opt/mylampiphant/assemble-jvb-xmpp.sh ]; then
    /opt/mylampiphant/assemble-jvb-xmpp.sh
fi

exec /init
