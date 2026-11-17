# diagramsnet (draw.io)

Per-customer draw.io editor: stack `diagramsnet_c_<customer>`, default domain `draw.<domain>`.
Image: `jgraph/drawio:32.6.10` (official, linux/amd64 + linux/arm64). No database, no data volume.

Why per customer: the editor is stateless (diagrams are saved by the browser, as a download or in
the storage the user picks), so a second instance per domain would only cost RAM.

## RAM

Tomcat/JVM: about 200 MB idle, 300-400 MB while exporting large diagrams. `mem_limit` 448m,
heap capped with `JAVA_MAX_HEAP` (default 256 MB).

## Options

| Variable | Values | Default | Effect |
|---|---|---|---|
| `AUTH_PROTECT` | `true` \| `false` | `false` | Traefik ForwardAuth via the host Authelia (LDAP users). draw.io has no accounts of its own. |
| `EXTERNAL_ACCESS` | `true` \| `false` | `true` | `false`: only `IPALLOW_RANGES` (VPN/LAN) |
| `HTTP_REDIRECT` | `true` \| `false` | `true` | HTTP→HTTPS |
| `LETSENCRYPT_METHOD` | `acme` \| `dns01` | `acme` | certificate resolver |

Not included: the self-contained mode (`DRAWIO_SELF_CONTAINED`) needs `jgraph/export-server`,
which is published for linux/amd64 only. PNG/SVG export runs in the browser; PDF export uses
draw.io's default (public) export service.

```bash
app.sh diagramsnet add <customer>
app.sh diagramsnet add <customer> --var APPDOMAIN=draw.example.com --var AUTH_PROTECT=true
```
