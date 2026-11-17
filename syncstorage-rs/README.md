# syncstorage-rs (Firefox Sync server)

Mozilla's Sync server (syncstorage + tokenserver in one Rust binary), PostgreSQL backend.
Stack `syncstorage-rs_c_<customer>`, default domain `ffsync.<domain>`.

## Image (built by Komodo)

Mozilla publishes linux/amd64 images only (`ghcr.io/mozilla-services/syncstorage-rs/syncserver-postgres`).
On ARM64 the compose file builds from the pinned upstream tag with a git build context:

```
build:
  context: https://github.com/mozilla-services/syncstorage-rs.git#0.25.0
  args: { SYNCSTORAGE_DATABASE_BACKEND: postgres, TOKENSERVER_DATABASE_BACKEND: postgres }
image: syncstorage-rs-local:0.25.0-postgres
```

The Rust release build needs about 2-3 GB RAM and 30-60 minutes on a 2-core ARM64 host.
On a 4 GB server, stop other stacks during the first deploy (or build elsewhere and push).

## RAM (runtime)

syncserver 30-80 MB, PostgreSQL 50-150 MB: about 100 MB idle, 250 MB with a few active users.
Limits: 192m / 256m.

## Login and access

Firefox still signs in with a Mozilla account (accounts.firefox.com); only the encrypted sync
data is stored here. LDAP/OIDC is not possible without self-hosting the whole Mozilla accounts
stack. Any Mozilla account that knows the URL can use the server; use `EXTERNAL_ACCESS=false`
(VPN/LAN only) if that is not wanted.

Firefox desktop: `about:config` → `identity.sync.tokenserver.uri` =
`https://<APPDOMAIN>/1.0/sync/1.5`, then sign in again.

## Options

| Variable | Values | Default |
|---|---|---|
| `VOLUME_MODE` | `bind` \| `named_bind` \| `managed` | `bind` |
| `EXTERNAL_ACCESS` | `true` \| `false` | `true` |
| `HTTP_REDIRECT` | `true` \| `false` | `true` |
| `LETSENCRYPT_METHOD` | `acme` \| `dns01` | `acme` |

Secrets (`SYNC_MASTER_SECRET`, metrics hash secret, DB password) stay in the persistent config and
in `<data_dir>/secrets/{syncserver,db}.env` (chmod 600), never in the Komodo `.env`.
