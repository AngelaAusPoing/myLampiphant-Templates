# DokuWiki (myLampiphant template)

Per-domain wiki: stack name `dokuwiki_d_<domain_normalized>`.
Image: `lscr.io/linuxserver/dokuwiki` (ARM64). No database.

The live stack `dokuwiki_d_wiki_lapha_de` was installed with the previous
template. This revision only changes the templates; it does not redeploy or
restart that wiki.

## Options

| Variable | Values | Default | Effect |
|---|---|---|---|
| `DOKUWIKI_AUTH` | `plain` \| `ldap` | `plain` | Built-in users (`authplain`) or host OpenLDAP (`authldap`) |
| `DOKUWIKI_ACCESS` | `open` \| `closed` | `open` | `closed`: `* @ALL 0`, `* @user 8`, self-registration off |
| `VOLUME_MODE` | `bind` \| `named_bind` \| `managed` | `bind` | data volume style |
| `HTTP_REDIRECT` | `true` \| `false` | `true` | HTTP→HTTPS |
| `LETSENCRYPT_METHOD` | `acme` \| `dns01` | `acme` | Traefik certificate resolver |
| `EXTERNAL_ACCESS` | `true` \| `false` | `true` | public vs IP allow-list |
| `AUTH_PROTECT` | `true` \| `false` | `false` | Traefik ForwardAuth via host Authelia |

LDAP-only placeholders (filled by `app.sh` from the profile, override with `--var`):

- `LDAP_SERVER` — default `ldap://ldap:389` on the internal `ldap-shared` network
- `LDAP_BIND_DN` — default `cn=readonly,ou=system,dc=lampiphant,dc=de` (same read-only account as the mailserver)
- `LDAP_USER_TREE` — default `ou=people,o=<customer>,dc=lampiphant,dc=de`
- `LDAP_GROUP_TREE` — default `ou=groups,o=<customer>,dc=lampiphant,dc=de`
- `LDAP_ADMIN_GROUP` — LDAP group CN mapped to DokuWiki superuser (default `wiki-admin`)
- `LDAP_BIND_PW_FILE` — host path of the read-only bind secret (default `/opt/docker-data/_host_/ldap/secrets/readonly.pw`). Never put the password in Komodo `.env` or in git.

```bash
app.sh dokuwiki add <customer> <domain>
app.sh dokuwiki add <customer> <domain> --var DOKUWIKI_AUTH=ldap --var DOKUWIKI_ACCESS=closed
app.sh dokuwiki add lampiphant_de wiki.lampiphant.de --var DOKUWIKI_AUTH=ldap --var DOKUWIKI_ACCESS=closed
```

Finish the web installer first (creates `conf/local.php` and the initial local
admin). Then restart the stack so `custom-cont-init.d/10-apply-options.sh`
writes `local.protected.php`. Until that restart, `install.php` may still be
reachable; after a restart it should be gone, as with the lapha.de wiki.

When `DOKUWIKI_AUTH=ldap`, the installer-created local admin can no longer log
in (`authtype=authldap`). Members of `LDAP_ADMIN_GROUP` become superusers.
`ou=groups` already exists per customer, but no groups have been created yet
and `ldapadmin.sh` has no `add-group` command. Create a `groupOfNames` entry
(for example `cn=wiki-admin,ou=groups,o=<customer>,dc=lampiphant,dc=de`) with
`member` DNs before you rely on LDAP logins for administration. The `memberOf`
overlay is already enabled on the directory.

Users are `inetOrgPerson` under `ou=people,o=<customer>,dc=lampiphant,dc=de`
(`uid`, `cn`, `mail`). Most existing accounts live under `o=lampiphant_de`.
A wiki for another customer defaults to that customer's own subtree; override
`LDAP_USER_TREE` / `LDAP_GROUP_TREE` if the wiki should use a different branch.

## Synology DokuWiki migration

Use this when moving an existing Synology wiki (planned target: lampiphant.de,
not the current lapha.de test wiki).

Typical Synology / stock DokuWiki layout:

- `data/pages` — page wikitext
- `data/media` — uploaded files
- `data/meta` — page metadata (needed so history and last-edit stay consistent)
- `data/attic` — old page revisions
- `data/media_attic`, `data/media_meta` — copy these too if present
- `conf/` — local config, ACL, users, plugins.local
- `lib/plugins/` — extra plugins (not the bundled ones)

linuxserver paths on this host (inside the data volume):

- `config/dokuwiki/data/pages`
- `config/dokuwiki/data/media`
- `config/dokuwiki/data/meta`
- `config/dokuwiki/data/attic`
- `config/dokuwiki/data/media_attic`
- `config/dokuwiki/data/media_meta`
- `config/dokuwiki/conf`
- `config/dokuwiki/lib/plugins`

Suggested steps (do not run them against wiki.lapha.de):

1. Install a fresh stack for the target domain and complete the web installer once.
2. Stop the stack (`app.sh dokuwiki stop <customer> <domain>`).
3. Copy `pages`, `media`, `meta`, `attic` (and media_attic / media_meta) over the
   new `config/dokuwiki/data/` trees. Keep the linuxserver `savedir` from the
   new `local.php` (`/app/www/public/data`); do not paste a Synology `savedir`.
4. Merge `conf/` carefully:
   - Keep the new `local.php` (paths, `savedir`) and let `local.protected.php`
     stay under the start script's control (auth, LDAP, closed-wiki flags).
   - Copy `acl.auth.php` if you want the old page-level rules, then re-apply
     `closed` on the next start (the script only adjusts the `* @ALL` /
     `* @user` catch-alls and leaves more specific rules in place).
   - Copy `users.auth.php` only if you stay on `plain` auth. With `ldap`,
     accounts come from the directory.
   - Do not copy Synology-only paths, `install.php`, or credentials into git.
5. Copy extra plugins into `config/dokuwiki/lib/plugins/`. Skip bundled plugins
   that the image already ships (`authldap`, `authplain`, `acl`, …).
6. `chown -R 1000:1000` on the data volume `config/` tree.
7. Start the stack and check a few pages, media links, and a historic revision.

If the Synology wiki used a different auth backend or farm setup, stop and
compare `conf/local.php` before overwriting anything.
