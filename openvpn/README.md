# OpenVPN app template

Per-customer OpenVPN stack: `openvpn_c_<customer>`. VPN is optional; a customer
may run WireGuard, OpenVPN, both, or neither. This directory is the template
only — it does not deploy a stack, change Traefik, open host port 443, or
install/configure sslh.

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
| `OVPN_TRANSPORT` | `udp1194` (default), `tcp443_sslh` | How clients reach the server |
| `OVPN_PORT` | `1194` | Host/container UDP port when `udp1194` |
| `OVPN_BACKEND_PORT` | `1194` | `127.0.0.1` TCP port mapped to container 443 when `tcp443_sslh` |
| `OVPN_MEM_LIMIT` | `256m` | compose `mem_limit` |
| `OVPN_ENDPOINT` | auto (host IPv4 or FQDN) | `remote` in client profiles |
| `OVPN_SUBNET_INDEX` | auto 1–254 | Shared `<n>` with WireGuard |
| `OVPN_IPV4_CIDR` | `10.51.<n>.0/24` | Client subnet (see `../wireguard/SUBNETS.md`) |
| `OVPN_DNS` | `1.1.1.1,9.9.9.9` | Two resolvers pushed to clients |
| `OVPN_CLIENT_NAME` | `initial` | First cert the image creates on first start |
| `EXTERNAL_ACCESS` | `false` | No Traefik HTTP router |

Jinja2 in `compose.yaml.template` branches on `SPRW__VOLUME_MODE` and
`SPRW_OVPN_TRANSPORT`.

## Transport: UDP 1194 vs TCP 443

- **`udp1194`**: publishes `!!OVPN_PORT!!/udp` on the host. `install.sh` opens
  that UDP port in ufw if ufw is active (same idea as WireGuard). Suitable
  when the client's network allows UDP 1194.
- **`tcp443_sslh`**: OpenVPN listens on **TCP 443 inside the container**, so
  generated client profiles use `remote <endpoint> 443` (works from hotels
  that only allow 443). The host publishes **only**
  `127.0.0.1:!!OVPN_BACKEND_PORT!!:443/tcp`. Public port 443 is left with
  Traefik. **Sharing host 443** (sslh protocol mux, or Traefik TCP
  passthrough / SNI) is a later step and needs a **maintenance window and
  Angela's approval**. This template must not be used as a reason to change
  Traefik, the firewall for 443, or sslh.

Until that hand-off exists, a `tcp443_sslh` stack is reachable on localhost
only (for tests or a later frontend).

Several customers on public 443 at once is an open design point: sslh
typically has one OpenVPN backend; Traefik TCP with SNI could route by
hostname. See "Open questions" below.

## Client certificates

There is no web UI (unlike wg-easy). After deploy, on the host:

```
ovpnadmin.sh add-client <name>
ovpnadmin.sh export-client <name> <dir>   # writes <name>.ovpn, chmod 600, never printed
ovpnadmin.sh list
ovpnadmin.sh revoke-client <name>
ovpnadmin.sh status
```

The image always creates one first client (`OVPN_CLIENT_NAME`, default
`initial`) when PKI is initialised. Export or revoke it deliberately. PKI and
`.ovpn` files live under the data volume and must not be committed.

## Install (later, not done by this change)

```
app.sh openvpn add <customer>
app.sh openvpn add <customer> --var OVPN_TRANSPORT=tcp443_sslh
```

`install.sh` is idempotent, refuses `_host_`, reuses the shared
`vpn-subnets.conf` index, and does not overwrite an existing `vpn.env` or PKI.

## Files

| File | Purpose |
|------|---------|
| `compose.yaml.template` | Stack (Jinja2 for transport + volume mode) |
| `docker-env.template` | Non-secret values sent to Komodo |
| `profile.template` | Defaults and placeholders |
| `install.sh.template` | Host prep before Komodo deploy |
| `ovpnadmin.sh.template` | Client cert helper |
| `entrypoint.sh` | PATH + image `run.sh` |
| `openvpn-shim.sh` | Runs patch + firewall, then real `openvpn` |
| `patch-config.sh` | Custom subnet + split-tunnel in `server.conf` |
| `ovpn-firewall.sh` | Isolation iptables loop |

## Open questions for Angela

1. **sslh vs Traefik TCP on 443.** Protocol mux (sslh) is simple but normally
   has a single OpenVPN backend. Traefik TCP passthrough with SNI would allow
   per-customer hostnames on the same 443, but needs a planned cutover.
2. **One vs many `tcp443_sslh` stacks.** If only one customer needs hotel TCP
   443, sslh to that backend is enough. If several do, we need SNI or extra
   public IPs.
3. **First client cert.** Keep and export `initial`, or revoke it after the
   first named client is added?
4. **Image pin.** Only the `latest` tag is published; the compose file pins
   the digest from 2026-11-09. OK, or rebuild/mirror ourselves later?
