# Matrix (Synapse + Element)

Generic myLampiphant template. Install with app.sh, not the retired `matrix.sh`.

```bash
app.sh matrix add <customer> <apex-domain>
# example
app.sh matrix add lapha_de lapha.de
```

The stack is named `matrix_d_<apex_normalized>` (per-domain, like WordPress and Ghost).

| Role | URL |
| --- | --- |
| Homeserver name | `@user:<apex-domain>` e.g. `@alice:lapha.de` |
| Synapse (client + federation on 443) | `https://matrix.<apex-domain>` |
| Element | `https://chat.<apex-domain>` |
| Client/server discovery | `https://<apex-domain>/.well-known/matrix/{client,server}` |

The well-known Traefik rule is limited to `PathPrefix(/.well-known/matrix)` with priority 100, so a website can keep serving the apex host. Port 8448 is not used.

Registration is disabled. Create users with `register_new_matrix_user` and the shared secret from the persistent config (`/opt/docker-data/<customer>/_config_/matrix_d_<domain>.env`). Do not print that secret. Signing keys and passwords are created once and are not regenerated on redeploy.

Memory limits: Synapse 768m, PostgreSQL 256m, Redis 64m, Element 64m, well-known 32m (about 1.2 GB plus headroom). Jinja2 options are the usual `VOLUME_MODE`, `HTTP_REDIRECT`, `LETSENCRYPT_METHOD`, `EXTERNAL_ACCESS`. Config files are written by `install.sh` into the data directory and bind-mounted with absolute paths.
