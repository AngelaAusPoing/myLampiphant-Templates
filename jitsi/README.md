# Jitsi Meet (myLampiphant template)

Templates only. Do not deploy on the CAX11 while other stacks are starting:
the host videobridge and a customer UI already need several hundred MB, and
Jibri recording needs about 2 GB on its own.

## Architecture

Two roles, one app name `jitsi`, one template directory:

| Role | Stack name | What runs |
|---|---|---|
| Host (customer `_host_`) | `jitsi` | Shared **JVB** (Videobridge). UDP `10000` is bound once per host. |
| Customer | `jitsi_c_{customer}` | Own **web** UI, **Prosody**, **Jicofo**, optional Excalidraw whiteboard and Jibri. Branding and options are per customer. |

This is the split Angela asked for: each customer has a configurable meeting
UI; the central element (Jitsi Videobridge, JVB) lives under `_host_` and is
shared, because UDP/10000 can only be published once.

### How one JVB serves many customers

Official `docker-jitsi-meet` can pass a comma-separated `XMPP_SERVER` list, but
every entry then shares the same `XMPP_AUTH_DOMAIN`, brewery MUC and
`JVB_AUTH_PASSWORD`. That is meant for several servers of the *same* shard, not
for isolated customer Prosodies.

Jitsi Videobridge itself does support multiple XMPP client connections with
different hostname, domain, password and MUC (see
[jitsi-videobridge doc/muc.md](https://github.com/jitsi/jitsi-videobridge/blob/master/doc/muc.md)).
The official `jvb.conf` template ends with `include "custom-jvb.conf"`.

This template uses that hook:

- Each customer Prosody has unique XMPP domains (`meet.{customer}`,
  `auth.meet.{customer}`, `internal-muc.meet.{customer}`, …) and its own
  `JVB_AUTH_PASSWORD`.
- Customer `install.sh` writes a drop-in to
  `/opt/docker-data/_host_/jitsi/xmpp-servers/{stack}.conf` and rebuilds
  `custom-jvb.conf`.
- The host JVB starts with `JVB_DISABLE_XMPP=1` so the official single-shard
  env config is not used, then loads the drop-ins.
- Customer Prosody is attached to the `jitsi-shared` Docker network with the
  alias `xmpp-{stack}`.

Adding or removing a customer restarts the host JVB so it reconnects. That
briefly drops any meetings that are in progress on the shared bridge.

Limits of this approach:

- One JVB on one public UDP port is a single media bottleneck (CPU, RAM and
  especially uplink bandwidth).
- The number of customer shards is not hard-capped by JVB, but each XMPP
  connection and each concurrent conference costs RAM on the shared bridge.
- JVB cannot be given a different advertised IP or UDP port per customer.
- Runtime addition of XMPP servers is documented for JVB, but docker-jitsi-meet
  does not expose a stable reload hook; this template restarts JVB.

### Networks

- `jitsi-shared` — regular bridge (not `--internal`): JVB must publish UDP
  10000 and use STUN. Created by `ensure-networks.sh`.
- `c_{customer}-net` — customer web, Prosody, Jicofo, optional extras.
- `proxy-shared` — Traefik to the customer web container only. JVB stays off it.

### Installation

Host (normally automatic when the first customer is installed):

```bash
app.sh jitsi add _host_
# optional: --var JVB_ADVERTISE_IPS=203.0.113.10 --var JVB_PORT=10000
```

Customer (0-1 stack per customer, name `jitsi_c_{customer}`). Pass the public
meeting host with `--var`, **not** as a positional domain (a positional domain
would create `jitsi_d_{domain}`):

```bash
app.sh jitsi add <customer> --var APPDOMAIN=meet.example.com
app.sh jitsi add <customer> --var APPDOMAIN=meet.example.com --var JITSI_WHITEBOARD=true
```

`profile.template` declares `SPRW__REQUIRES_HOST_APPS=jitsi`. app.sh installs
the host stack first when it is missing. This is a generic hook, not a Jitsi
special case.

## Options (Jinja2 buttons)

- `JITSI_WHITEBOARD` — `true`/`false` (default `false`). Adds
  `jitsi/excalidraw-backend` on the customer stack. The Jitsi web nginx
  proxies `/socket.io/` so no extra public hostname is required.
- `JITSI_RECORDING` — `true`/`false` (default `false`). Adds Jibri on the
  customer stack. Needs about 2 GB RAM plus `shm_size: 2gb`. Do not enable on
  the CAX11 (4 GB) together with other apps.

Plus the usual globals: `VOLUME_MODE`, `HTTP_REDIRECT`, `LETSENCRYPT_METHOD`,
`EXTERNAL_ACCESS`.

Customer-configurable placeholders include `APPDOMAIN`, `DEFAULT_LANGUAGE`,
`APP_NAME` (UI title), `ENABLE_AUTH`, `ENABLE_GUESTS`, `ENABLE_PREJOIN_PAGE`,
`RESOLUTION`, `BRANDING_DATA_URL`.

## RAM estimates (ARM64)

| Piece | Typical mem_limit | Notes |
|---|---|---|
| Host JVB | 768m | Grows with conferences; Java heap is capped below the limit. |
| Customer web | 128m | nginx + Jitsi Meet static UI. |
| Customer Prosody | 128m | |
| Customer Jicofo | 384m | Java focus component. |
| Whiteboard | 256m | Excalidraw backend, ARM64 image available. |
| Jibri | 2048m | Per recording; plus 2 GB SHM. |

Per customer without extras: about 640–700 MB. With whiteboard: add ~256 MB.
With Jibri: add ~2 GB. Host JVB: plan 768 MB idle-to-moderate, more under load.

## ARM64

Images are pinned to `stable-11248-3` (`jitsi/web`, `prosody`, `jicofo`, `jvb`,
`jibri`). Jibri gained official ARM64 Chrome support in `stable-11248`.
`jitsi/excalidraw-backend:2026.10.0` publishes linux/arm64. Still verify the
pulled digest on this host before the first real deploy.

## UDP 10000 and TCP fallback

Open **UDP 10000** (or `JVB_PORT`) on the host firewall to the JVB. Clients on
restricted networks (UDP blocked, typical hotel Wi-Fi) will fail without a TURN
server. The old JVB TCP harvester is deprecated in current docker-jitsi-meet.
A later coturn (or TURN on TCP 443 via sslh) is the supported fallback; it is
not part of this template. Do not bind JVB TCP on 443: Traefik (and planned
OpenVPN/sslh) already use it.

## Secrets

Passwords (`JICOFO_AUTH_PASSWORD`, `JVB_AUTH_PASSWORD`, Jibri accounts) are
created by app.sh (`!!NEW_PASSWORD!!`) and written only to the persistent
config and to `!!DATA_DIR!!/secrets/`. They are not placed in the Komodo `.env`.
Drop-ins under `_host_/jitsi/xmpp-servers/` are mode 600 and stay on the host.

## Files

- `compose.yaml.template`, `docker-env.template`, `profile.template`
- `install.sh.template`, `purge.sh.template`
- `assemble-jvb-xmpp.sh`, `jvb-entrypoint.sh` (host JVB)
