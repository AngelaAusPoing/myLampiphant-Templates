# VPN subnet allocation

This scheme is shared by the WireGuard template and (later) OpenVPN.

| VPN        | Prefix per customer | Notes                                      |
|------------|---------------------|--------------------------------------------|
| WireGuard  | `10.50.<n>.0/24`    | One stack `wireguard_c_<customer>`         |
| OpenVPN    | `10.51.<n>.0/24`    | Host stack; one `/24` reserved per customer |
| WireGuard IPv6 ULA | `fd50:<n>::/64` | Set at init; IPv6 in the tunnel is off by default |

`<n>` is an integer from 1 to 254. The same `<n>` is used for both VPNs of one
customer. 0 and 255 are reserved.

These ranges sit outside Docker's `172.16.0.0/12` and the already used
`10.0.0.0/24`, `10.0.1.0/24` and `10.200.0.0/24`.

The live mapping (customer → `<n>`) is written on the host at
`/opt/docker-data/_host_/_config_/vpn-subnets.conf` when the first VPN app
for that customer is installed. That file is host-only and is not committed.

Example: the first customer that gets a VPN receives `n=1`, so WireGuard
`10.50.1.0/24`, OpenVPN `10.51.1.0/24` and ULA `fd50:1::/64`.

You can also set `!!WG_IPV4_CIDR!!` / `!!WG_SUBNET_INDEX!!` explicitly in the
persistent config before install; `install.sh` will record that choice and
refuse to reuse an index or CIDR that is already taken.
