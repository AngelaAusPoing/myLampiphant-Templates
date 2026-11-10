#!/bin/sh
# Wrapper around the image CMD (/opt/src/run.sh). Puts our openvpn shim
# first on PATH so we can patch server.conf (custom subnet, split-tunnel)
# and start the isolation firewall just before OpenVPN is exec'd.
set -e
export PATH="/opt/mylampiphant/bin:${PATH}"
exec /opt/src/run.sh
