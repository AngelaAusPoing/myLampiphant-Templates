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
data is stored here. LDAP/OIDC would need the whole Mozilla accounts stack. A proxy login
(Authelia ForwardAuth, basic auth, also `user:pass@` in the URL) cannot be put in front:
Firefox (desktop: `RESTRequest` with `LOAD_ANONYMOUS`; Android/iOS: application-services)
sends its own `Authorization` header (Bearer to the tokenserver, Hawk to the storage) and
no cookies, and follows no login redirects.

Access is limited instead by:

- `PATH_PROTECT=true` (default): the tokenserver is only routed under
  `https://<APPDOMAIN>/<ACCESS_PATH>/1.0/sync/1.5`; without it nobody gets a sync token.
  Storage requests stay at `/1.5/...` because their Hawk signature covers the path; they
  only work with a token from the tokenserver. Everything else (`/`, heartbeat, FxA webhook)
  is not routed. `ACCESS_PATH` is generated once (persistent config); it is a capability URL,
  not a password, and appears in the Traefik labels (Komodo) and in the client settings.
- `ALLOW_NEW_USERS=false` (upstream `SYNC_TOKENSERVER__ALLOW_NEW_USERS`): only Mozilla
  accounts that already synced here keep working. Onboarding: leave `true`, let every user
  sign in once, then set `false` and redeploy.
- `EXTERNAL_ACCESS=false`: VPN/LAN only.

Firefox desktop: `about:config` → `identity.sync.tokenserver.uri` =
`https://<APPDOMAIN>/<ACCESS_PATH>/1.0/sync/1.5`, then sign in again.
Firefox Android: Settings → About Firefox → tap the logo 5× → back → "Sync debug" →
custom Sync server. Firefox iOS: Settings → tap the version 5× → "Advanced Sync Settings".

## Options

| Variable | Values | Default |
|---|---|---|
| `VOLUME_MODE` | `bind` \| `named_bind` \| `managed` | `bind` |
| `EXTERNAL_ACCESS` | `true` \| `false` | `true` |
| `PATH_PROTECT` | `true` \| `false` | `true` |
| `ALLOW_NEW_USERS` | `true` \| `false` | `true` |
| `HTTP_REDIRECT` | `true` \| `false` | `true` |
| `LETSENCRYPT_METHOD` | `acme` \| `dns01` | `acme` |

Secrets (`SYNC_MASTER_SECRET`, metrics hash secret, DB password) stay in the persistent config and
in `<data_dir>/secrets/{syncserver,db}.env` (chmod 600), never in the Komodo `.env`.
