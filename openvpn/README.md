# OpenVPN app template

Per-customer OpenVPN stack: `openvpn_c_<customer>`. VPN is optional; a customer
may run WireGuard, OpenVPN, both, or neither. This directory is the template
only — it does not deploy a stack, change Traefik's static config, open or
rebind host port 443, or install/configure sslh.

## Image

`hwdsl2/openvpn-server` pinned to the multi-arch digest of `latest` as of
2026-11-09 (UTC):

```
hwdsl2/openvpn-server:latest@sha256:5b47bd53222328322f2af9984acfe42b91ab23f76c3dbc4086b53d4fc8325030
```

Why this image:

- Actively maintained (Lin Song / hwdsl2; last push 2026-11-09). Alpine 3.23,
  current OpenVPN, EasyRSA, AES-128-GCM, SHA256, tls-crypt.
- Official multi-arch images: `linux/amd64`, `linux/arm64`, `linux/arm/v7`.
  Required for the CAX11 (ARM) host.
- Client lifecycle via `ovpn_manage` (add / list / revoke).
- `kylemanna/openvpn` is unmaintained. The well-kept fork `lisenet/openvpn`
  publishes amd64 only. linuxserver OpenVPN-AS is deprecated. `d3vilh/openvpn-server`
  last released in 2024.

The image hardcodes the VPN subnet `10.8.0.0/24` and a full-tunnel
`redirect-gateway`. A small entrypoint shim patches `server.conf` on every
start to the allocated `10.51.<n>.0/24` and split-tunnel routes, and the
isolation firewall drops anything except this customer's Docker network.

Anonymous usage pings of the image are disabled (`VPN_DISABLE_USAGE_COUNTS=1`).

## Options

| Variable | Values / default | Role |
|----------|------------------|------|
| `VOLUME_MODE` / `SPRW__VOLUME_MODE` | `bind` (default), `named_bind`, `managed` | Where `/etc/openvpn` is stored |
| `OVPN_TRANSPORT` | `udp1194` (default), `tcp443_tls` | How clients reach the server |
| `OVPN_PORT` | `1194` | Container listen port; also the host UDP port when `udp1194` |
| `OVPN_HOSTNAME` | `vpn.<customer DOMAIN>` | Public TLS name for `tcp443_tls` (`HostSNI`) |
| `LETSENCRYPT_METHOD` | `acme` (default), `dns01` | Traefik certresolver for the TCP router (`letsencrypt` or `letsencrypt-dns`) |
| `OVPN_MEM_LIMIT` | `256m` | compose `mem_limit` |
| `OVPN_ENDPOINT` | auto (host IPv4 or FQDN) | `remote` in client profiles for `udp1194` |
| `OVPN_SUBNET_INDEX` | auto 1–254 | Shared `<n>` with WireGuard |
| `OVPN_IPV4_CIDR` | `10.51.<n>.0/24` | Client subnet (see `../wireguard/SUBNETS.md`) |
| `OVPN_DNS` | `1.1.1.1,9.9.9.9` | Two resolvers pushed to clients |
| `OVPN_CLIENT_NAME` | `initial` | First cert the image creates on first start (revoked after the first named client) |
| `EXTERNAL_ACCESS` | `false` | No Traefik HTTP router (TCP labels are attached independently for `tcp443_tls`) |

Jinja2 in `compose.yaml.template` branches on `SPRW__VOLUME_MODE`,
`SPRW_OVPN_TRANSPORT` and `SPRW__LETSENCRYPT_METHOD`.

Option enum for Docusaurus buttons: `OVPN_TRANSPORT` = `udp1194` | `tcp443_tls`.

## Transport: UDP 1194 vs TCP 443 (TLS)

- **`udp1194`**: publishes `!!OVPN_PORT!!/udp` on the host. `install.sh` opens
  that UDP port in ufw if ufw is active (same idea as WireGuard). Suitable
  when the client's network allows UDP 1194. The container is only on
  `c_<customer>-net`.

- **`tcp443_tls`**: for hotels and other networks that only allow TCP 443.
  OpenVPN listens on **TCP !!OVPN_PORT!! inside the container** (default 1194).
  **No host port is published.** Traefik already owns public 443 (`websecure`).
  The stack joins `proxy-shared` and adds a TCP router:

  `HostSNI(\`!!OVPN_HOSTNAME!!\`)` + `tls=true` +
  `tls.certresolver=letsencrypt` (or `letsencrypt-dns`).

  Traefik **terminates TLS** with a Let's Encrypt certificate and forwards
  **plain OpenVPN TCP** to the container. This is the simpler path: no stunnel
  sidecar on the server, no extra certificates in the stack, and several
  customers can share host 443 because Traefik routes by SNI.

  Raw OpenVPN TCP does **not** start with a TLS ClientHello, so Traefik cannot
  see SNI without a wrapper on the **client**. `ovpnadmin.sh export-client`
  writes a bundle: rewritten `.ovpn` (connects to `127.0.0.1:14194`), a
  stunnel client config (connects to `!!OVPN_HOSTNAME!!:443` with SNI and
  certificate checks), and setup notes for Linux, Windows, macOS, Android and
  iOS. Standard OpenVPN clients cannot do this TLS wrapping natively.

  This template must not be used as a reason to change Traefik's static
  config, the firewall for 443, or to install sslh. At deploy time (later)
  only Docker labels are added; `websecure` is already listening on 443.
  DNS for `OVPN_HOSTNAME` must point at the host so HTTP-01 (port 80) can
  issue the certificate. The current Traefik static config has the
  `letsencrypt` HTTP-01 resolver, not `letsencrypt-dns`.

## Client certificates

There is no web UI (unlike wg-easy). After deploy, on the host:

```
ovpnadmin.sh add-client <name>           # then revokes the auto-created "initial" cert
ovpnadmin.sh export-client <name> <dir>  # writes files, chmod 600, never printed
ovpnadmin.sh list
ovpnadmin.sh revoke-client <name>
ovpnadmin.sh revoke-initial              # same policy, for a manual retry
ovpnadmin.sh status
```

The image always creates one first client (`OVPN_CLIENT_NAME`, default
`initial`) when PKI is initialised. After the first **named** client is
added, `add-client` revokes `initial` automatically. `revoke-initial` refuses
to run if no other issued client exists. PKI and `.ovpn` files live under the
data volume and must not be committed.

## Install (later, not done by this change)

```
app.sh openvpn add <customer>
app.sh openvpn add <customer> --var OVPN_TRANSPORT=tcp443_tls
app.sh openvpn add <customer> --var OVPN_TRANSPORT=tcp443_tls --var OVPN_HOSTNAME=vpn.example.com
```

`install.sh` is idempotent, refuses `_host_`, reuses the shared
`vpn-subnets.conf` index, and does not overwrite an existing `vpn.env` or PKI.
For `tcp443_tls` it defaults `OVPN_HOSTNAME` to `vpn.<customer DOMAIN>` and
requires a DNS name (not an IP).

## Files

| File | Purpose |
|------|---------|
| `compose.yaml.template` | Stack (Jinja2 for transport + volume mode + certresolver) |
| `docker-env.template` | Non-secret values sent to Komodo |
| `profile.template` | Defaults and placeholders (option enums for Docusaurus) |
| `install.sh.template` | Host prep before Komodo deploy |
| `ovpnadmin.sh.template` | Client cert helper, revoke-initial, TLS bundle export |
| `CLIENT-TLS.md` | Client stunnel instructions (placeholders filled on export) |
| `stunnel-client.conf.template` | Reference stunnel client config |
| `entrypoint.sh` | PATH + image `run.sh` |
| `openvpn-shim.sh` | Runs patch + firewall, then real `openvpn` |
| `patch-config.sh` | Custom subnet + split-tunnel in `server.conf` |
| `ovpn-firewall.sh` | Isolation iptables loop |

## Decisions already taken

1. Public 443 is handled by **Traefik with a per-customer hostname**
   (`HostSNI`), not sslh.
2. **Several customers** may use TCP 443 at once (unique `OVPN_HOSTNAME` each).
3. The auto-created **`initial` client is revoked** after the first named
   client certificate is added.
4. The image stays **pinned to the `latest` digest** (the image has no other
   tags).

## Open questions

- HTTP-01 for a TCP-only Traefik router is expected to work (the challenge
  uses entrypoint `web` on port 80, independent of the TCP router). It has
  not been tested with a live stack yet. If issuance fails, a tiny HTTP
  router on the same hostname can be added later (watch ALPN vs the TCP
  router).
- The Traefik static config does not currently define `letsencrypt-dns`.
  The `dns01` option is templated like other apps, but will not work until
  that resolver exists. Out of scope here.
- Android and iOS have no comfortable TLS-wrapper client. Is
  `tcp443_tls` accepted as desktop-first, with UDP/WireGuard on mobile?
- Default hostname `vpn.<customer DOMAIN>`: ok, or should each customer
  pick a name up front?
