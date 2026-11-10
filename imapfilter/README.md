# imapfilter (myLampiphant)

Per-customer stack that runs [imapfilter](https://github.com/lefcha/imapfilter) (community image `ntnn/imapfilter`) in an internal 15-minute loop. It attaches only to the internal Docker network `mail-shared` and authenticates with a Dovecot **master user** (`mailbox*imapfilter`), never with the mailbox password.

- Config: `<data_dir>/config.lua` (chmod 600, not in git)
- Master password: `<data_dir>/secrets/imapfilter-master.pw` (chmod 600, not in git)
- `IMAPFILTER_TEST=true` (default): only log what would be moved
- On the mailserver: `docker exec -i mailserver setup dovecot-master add imapfilter`

## Activate on migration day

1. Stop the old host's cronjob *before* copying mailboxes (`*/15 * * * * ... imapfilter -c .../active-config.lua`).
2. Copy the mailboxes, then start this stack with `IMAPFILTER_TEST=true`.
3. Read the container logs (`Would move …`). Fix folders or rules if needed.
4. Set `IMAPFILTER_TEST=false` in the persistent config / compose environment and redeploy.
