# OpenVPN over TLS (tcp443_tls) — client setup

The server hostname is **!!OVPN_HOSTNAME!!** on TCP port 443.
Traefik terminates TLS (Let's Encrypt) and forwards plain OpenVPN TCP.
Your OpenVPN client must **not** connect to port 443 directly.

Standard OpenVPN clients (OpenVPN Community, OpenVPN Connect, Tunnelblick,
OpenVPN for Android, iOS OpenVPN Connect) cannot wrap the session in ordinary
TLS themselves. You run a small TLS wrapper (usually **stunnel**) that:

1. Listens on `127.0.0.1:!!OVPN_STUNNEL_LOCAL_PORT!!`
2. Opens a normal TLS connection to `!!OVPN_HOSTNAME!!:443` (SNI + certificate check)
3. Forwards raw OpenVPN TCP through that tunnel

Then start OpenVPN with `!!CLIENT_NAME!!.ovpn`, which already points at
`127.0.0.1:!!OVPN_STUNNEL_LOCAL_PORT!!`.

Uncomment the matching `CAfile` line in `!!CLIENT_NAME!!-stunnel.conf` before
the first start.

## Linux

```
# Debian/Ubuntu
sudo apt-get install stunnel4 openvpn
# Fedora
# sudo dnf install stunnel openvpn

# Uncomment the Debian or Fedora CAfile in the stunnel conf, then:
stunnel "!!CLIENT_NAME!!-stunnel.conf"
sudo openvpn --config "!!CLIENT_NAME!!.ovpn"
```

NetworkManager / `openvpn` systemd units also work if they use the rewritten
profile (remote 127.0.0.1). Start stunnel first.

## Windows

1. Install [stunnel](https://www.stunnel.org/downloads.html) and
   [OpenVPN Community](https://openvpn.net/community-downloads/) (or a GUI
   that can import a `.ovpn` file).
2. Copy `!!CLIENT_NAME!!-stunnel.conf` into the stunnel config directory.
   Set `CAfile` to the PEM CA bundle shipped with stunnel (or a Mozilla CA
   bundle).
3. Start the stunnel service.
4. Import `!!CLIENT_NAME!!.ovpn` and connect. The profile talks to
   `127.0.0.1:!!OVPN_STUNNEL_LOCAL_PORT!!` only.

## macOS

```
brew install stunnel openvpn
# Uncomment the macOS CAfile (/etc/ssl/cert.pem) in the stunnel conf, then:
stunnel "!!CLIENT_NAME!!-stunnel.conf"
sudo openvpn --config "!!CLIENT_NAME!!.ovpn"
```

Tunnelblick and Viscosity can import the `.ovpn` file, but stunnel must still
be running first. They have no built-in TLS wrapper for this mode.

## Android

There is no first-class, well-maintained path:

- OpenVPN for Android and OpenVPN Connect cannot wrap TLS natively.
- A separate stunnel app (or Termux + `stunnel` + OpenVPN) can work, but it is
  awkward to set up and some older stunnel apps are unmaintained.
- Hotel-style TCP 443 is therefore **desktop-first**. On a mobile network that
  allows UDP, prefer the `udp1194` transport or WireGuard.

## iOS

OpenVPN Connect for iOS cannot add a TLS wrapper. There is no supported
built-in stunnel equivalent. Use `udp1194` or WireGuard on iOS, or a desktop
for `tcp443_tls`.

## Alternatives

- **`udp1194`** (default): a normal OpenVPN profile, no stunnel, when UDP 1194
  is not blocked.
- **WireGuard**: simpler clients on every platform; UDP, so hotels that only
  allow TCP 443 will still block it.
- Other TLS wrappers (`gost`, `sslh` on the client, `ncat --ssl`) can replace
  stunnel if they speak ordinary TLS with SNI to `!!OVPN_HOSTNAME!!:443` and
  expose a local TCP port for OpenVPN. The `.ovpn` file stays the same.

## Checks

- DNS for `!!OVPN_HOSTNAME!!` must resolve to the VPN host.
- A browser opening `https://!!OVPN_HOSTNAME!!/` may show a TLS session with a
  valid certificate but no website (there is no HTTP router). That is expected.
- If OpenVPN connects to `:443` without stunnel, the handshake will fail
  (Traefik is expecting TLS, OpenVPN is not sending a TLS ClientHello with SNI).
