# pollaris (successor of OpenSondage / Framadate)

Framasoft archived the old OpenSondage/Framadate code in 2025; the current Framadate runs on
**Pollaris** (AGPL-3.0, Symfony, PostgreSQL). This template installs Pollaris.

Stack `pollaris_c_<customer>`, default domain `umfrage.<domain>`.

## Image (built by Komodo)

Upstream ships no production image (only a development Dockerfile). `install.sh` copies
`Dockerfile` + `pollaris-entrypoint.sh` into `<compose_dir>/image/`; Komodo builds
`pollaris-local:<POLLARIS_VERSION>` from there:

- base `dunglas/frankenphp:1.13.5-php8.4.27-alpine` (official, arm64), `composer:2.11.2`
- source: `git clone --branch 1.2.3 https://framagit.org/pollaris/pollaris.git`
- build: a few minutes and about 500 MB RAM on ARM64 (PHP extensions + composer)

Services: `web` (FrankenPHP, runs migrations on start), `worker` (Symfony Messenger,
`messenger:consume async scheduler_default`), `db` (`postgres:18.7-alpine`).

## RAM

web 60-120 MB, worker 40-80 MB, PostgreSQL 40-100 MB: about 150 MB idle, 250-350 MB under load.
Limits: 192m / 128m / 192m.

## Options

| Variable | Values | Default | Effect |
|---|---|---|---|
| `VOLUME_MODE` | `bind` \| `named_bind` \| `managed` | `bind` | PostgreSQL data |
| `AUTH_PROTECT` | `none` \| `admin` \| `all` | `none` | Authelia (LDAP) in front of nothing, of `/admin` + `/login`, or of the whole site |
| `MAIL_ENABLED` | `false` \| `true` | `false` | SMTP for admin links and notifications (`MAIL_HOST`, `MAIL_PORT`, `MAIL_USER`, `MAIL_PASSWORD`, `MAIL_FROM` in the persistent config) |
| `REQUIRE_EMAILS` | `false` \| `true` | `false` | poll authors must enter an e-mail |
| `EXTERNAL_ACCESS` | `true` \| `false` | `true` | `false`: only `IPALLOW_RANGES` |

LDAP/OIDC: Pollaris has only local admin accounts (`php bin/console app:user:create`) and no
LDAP/OIDC; participants never need an account. `AUTH_PROTECT` is the LDAP option.

Secrets (DB password, `APP_SECRET`, SMTP password) stay in the persistent config and in
`<data_dir>/secrets/{pollaris,db}.env` (chmod 600, rewritten by `install.sh`), never in the
Komodo `.env`.
