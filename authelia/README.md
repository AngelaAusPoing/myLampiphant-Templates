# Authelia (host app)

Central SSO for the host. Installed once under customer `_host_`. The stack is named `authelia` (no `_c_` / `_d_` suffix).

Nothing in this template is deployed automatically. Traefik static configuration is not changed; the ForwardAuth middleware is published by Docker labels as `authelia@docker`.

## Install (later, when RAM allows)

The host `ldap` stack must already be installed (read-only bind). `app.sh` will not auto-install it, because both apps live under `_host_`.

```bash
app.sh authelia add _host_ --var APPDOMAIN=auth.lampiphant.de
app.sh authelia add _host_ \
  --var APPDOMAIN=auth.lampiphant.de \
  --var COOKIE_DOMAINS=lampiphant.de,lapha.de,angelaauspoing.de
```

Create a DNS A record for every portal host before starting the stack. By default that is `auth.<cookie-domain>` for each cookie domain, plus `APPDOMAIN` if it is different.

## RAM

- Authelia: 128m (`AUTHELIA_MEM_LIMIT`)
- Optional Redis (only with `STORAGE_MODE=redis`): 64m
- Typical runtime is well below the limit; sqlite + in-memory sessions is the low-RAM default (~80–128m reserved).

## Options (Jinja2 / Docusaurus buttons)

| Option | Values | Default | Meaning |
|---|---|---|---|
| `VOLUME_MODE` | `bind`, `named_bind`, `managed` | `bind` | Data volume style (same as other apps) |
| `HTTP_REDIRECT` | `true`, `false` | `true` | HTTP → HTTPS on the portal |
| `LETSENCRYPT_METHOD` | `acme`, `dns01` | `acme` | Traefik certificate resolver |
| `EXTERNAL_ACCESS` | `true`, `false` | `true` | `false` restricts the portal with `iprestrict@file` (VPN). ForwardAuth for other apps still works on the Docker network. |
| `STORAGE_MODE` | `sqlite`, `redis` | `sqlite` | `sqlite` = SQLite + memory sessions. `redis` still uses SQLite for Authelia's SQL storage and adds Redis only for sessions (~64m extra). Redis cannot replace SQLite here. |
| `NOTIFIER` | `filesystem`, `smtp` | `filesystem` | Password-reset/enrolment messages. `filesystem` writes `/config/notification.txt`. `smtp` uses the host mailserver; set `SMTP_USER` / `SMTP_PASSWORD` to an existing mailbox first (no invented credentials). |

## Placeholders

| Placeholder | Example | Role |
|---|---|---|
| `APPDOMAIN` | `auth.lampiphant.de` | Primary portal hostname |
| `COOKIE_DOMAINS` | `lampiphant.de,lapha.de` | Session cookie domains (one per customer/registered domain) |
| `AUTH_HOSTS` / `ROUTER_RULE` | derived | Portal Host() list. Default: `APPDOMAIN` plus `auth.<each cookie domain>` |
| `DEFAULT_REDIRECTION_URL` | empty | Optional post-login redirect (must belong to a cookie domain) |
| `DEFAULT_POLICY` | `one_factor` | Access policy for cookie domains (`one_factor` or `two_factor`) |
| `LDAP_SERVER_HOST` | `ldap://ldap:389` | Directory on `ldap-shared` |
| `LDAP_BASE_DN` | `dc=lampiphant,dc=de` | Search base (whole tree: `o=<customer>/ou=people`) |
| `LDAP_BIND_DN` | `cn=readonly,ou=system,dc=lampiphant,dc=de` | Same read-only bind as the mailserver |
| `LDAP_USERNAME_ATTRIBUTE` | `uid` | Authelia username (`uid` or `mail`) |
| `SMTP_HOST` / `SMTP_PORT` | `mail.lapha.de` / `587` | Mailserver on `mail-shared` when `NOTIFIER=smtp` |

Secrets (`JWT_SECRET`, `SESSION_SECRET`, `STORAGE_ENCRYPTION_KEY`) are generated once by app.sh (`!!NEW_KEY!!`) and written to `DATA_DIR/secrets/`. The LDAP bind password is copied from `/opt/docker-data/_host_/ldap/secrets/readonly.pw`. None of these are written to the Komodo `.env`.

Password change/reset in Authelia is disabled: the bind is read-only. Use `ldapadmin.sh set-password`.

## Protecting another app (`AUTH_PROTECT=true`)

The Authelia container defines Traefik middleware `authelia@docker` (ForwardAuth at `http://authelia:9091/api/authz/forward-auth`). Other stacks on `proxy-shared` can opt in. The protected app and Authelia must both be running, and the request Host must fall under a configured cookie domain.

Snippet for a typical HTTPS router (chain with other middlewares when needed):

```yaml
      {%- if AUTH_PROTECT == "true" and EXTERNAL_ACCESS == "false" %}
      - "traefik.http.routers.!!STACKNAME!!.middlewares=authelia@docker,iprestrict@file"
      {%- elif AUTH_PROTECT == "true" %}
      - "traefik.http.routers.!!STACKNAME!!.middlewares=authelia@docker"
      {%- elif EXTERNAL_ACCESS == "false" %}
      - "traefik.http.routers.!!STACKNAME!!.middlewares=iprestrict@file"
      {%- endif %}
```

This option is already wired on the **dokuwiki** template (`AUTH_PROTECT`, default `false`). WordPress is left untouched (WIP). For any other app, add the same option and labels.

Authelia must be up before Traefik can resolve `authelia@docker`. If Traefik logs "middleware authelia@docker not found", start the Authelia stack first (or temporarily define the same middleware labels on Traefik itself — that would be a later, approved static-config change).

## LDAP notes

Users are `uid=<uid>,ou=people,o=<customer>,dc=lampiphant,dc=de` (`inetOrgPerson` + `lampiphantMailAccount`). Login accepts **uid or mail**. `ou=groups` exists per customer but no groups are provisioned yet; group-based access rules will only work after groups exist.

If two customers use the same `uid`, Authelia usernames collide when `LDAP_USERNAME_ATTRIBUTE=uid`. Prefer globally unique uids, or set the attribute to `mail`.

## Image

`authelia/authelia:4.39.28` (pinned; official multi-arch, including linux/arm64). Optional Redis: `redis:7.4-alpine`.
