# go-sync (Brave Sync Server v2)

Stack `go-sync_c_<customer>`, default domain `brave-sync.<domain>`.

## Images

- `go-sync`: Brave publishes no image and has no release tag since v0.1.21 (2023), while
  `master` is maintained. Komodo builds from a pinned commit with a git build context and the
  upstream Dockerfile (target `artifact`): `https://github.com/brave/go-sync.git#76745a6…`.
  Go build: a few minutes and about 1 GB RAM on ARM64.
- `amazon/dynamodb-local:3.3.2` (official, arm64): datastore, data in `<data_dir>/dynamodb`
- `amazon/aws-cli:2.40.4` (official, arm64): one-shot `dynamodb-init.sh` creates the table
  from `dynamodb-table.json` (copy of upstream `schema/dynamodb/table.json`) and enables TTL
- `redis:7.4.12-alpine` (official, arm64): cache only, no persistence

All backend containers are on a stack-internal network without internet; only go-sync is on
`proxy-shared`.

## RAM

go-sync 15-40 MB, DynamoDB Local (Java) 200-300 MB, Redis 5-20 MB: about 250 MB idle,
350 MB under load. Limits: 128m / 384m (heap `DYNAMODB_HEAP`=192 MB) / 64m.

## Login and access

Brave clients authenticate with their sync chain (sync code); there are no user accounts, so
LDAP/OIDC does not apply. Anyone who knows the URL can create a chain; use
`EXTERNAL_ACCESS=false` (VPN/LAN only) to restrict it.

Brave desktop: start with `--sync-url=https://<APPDOMAIN>/v2`. On mobile, a custom sync URL is
not an official setting; check the client before relying on it.

## Options

| Variable | Values | Default |
|---|---|---|
| `VOLUME_MODE` | `bind` \| `named_bind` \| `managed` | `bind` |
| `EXTERNAL_ACCESS` | `true` \| `false` | `true` |
| `HTTP_REDIRECT` | `true` \| `false` | `true` |
| `LETSENCRYPT_METHOD` | `acme` \| `dns01` | `acme` |
