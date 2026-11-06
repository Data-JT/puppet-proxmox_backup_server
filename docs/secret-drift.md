# Secret drift detection

How the module detects and enforces secrets that PBS does not return over its API, and how it
keeps them out of logs and reports.

Every secret this module manages is detected and enforced: changing a secret in Hiera, and
nothing else, rotates it on the next run.

## Where secrets are compared

PBS does not return most of these secrets over its API, but it persists them on the node. The
module reads those copies to decide whether the stored secret still matches the declared one.

| Attribute | Compared against | Stored as |
|---|---|---|
| `pbs_realm.client_key` | the API response itself | plaintext in `domains.cfg` |
| `pbs_realm.bind_password` | `ldap_passwords.json` | plaintext, `0600 root:root` |
| `pbs_remote.password` | `remote.cfg` | base64, `0640 root:backup` |
| `pbs_s3_endpoint.secret_key` | `s3.cfg` | plaintext, `0640 root:backup` |
| `pbs_notification_target.smtp_password` / `.token` / `.secret` | `notifications-priv.cfg` | plaintext (webhook values base64), `0600 root:root` |
| `pbs_user.password` | `shadow.json` | yescrypt hash, `0600 root:root` |

All paths are under `/etc/proxmox-backup/`. A secret is sent to PBS only when it no longer
matches the stored copy.

`pbs_api_token` secrets are the exception: PBS returns a generated token secret once, at
creation, and stores only a hash afterwards, so there is nothing to compare against. See
[API tokens](api-tokens.md).

## Requirements and failure mode

Reading those copies requires the Puppet agent to run on the PBS node as root. If a resource
declares such a secret and its store cannot be read, the run fails with an error naming the
attribute and the path. It does not report the resource as in sync: that would silently stop
enforcing the secret precisely where nobody can see it. Resources that declare no node-stored
secret are unaffected.

`pbs_realm.client_key` needs no on-node access, because PBS returns it over the API.

## User passwords and shadow.json

All changes go through the REST API, with one exception: `pbs_user` passwords. A password update
is written to `/etc/proxmox-backup/shadow.json` as a yescrypt hash generated via `libcrypt.so.1`
(libxcrypt), and `password_login => false` removes the user's hash from the same file (under
PBS's own lock, written atomically).

The API cannot be used for this. `PUT /access/password` requires `confirmation-password`, the
user's current password, unless authenticated as `root@pam`, and the current password is
precisely what is unknown once it has drifted. `proxmox-backup-manager user update --password`
is documented as ignored, so the module does not call the `proxmox-backup-manager` CLI at all.

Password management works only for users in the `@pbs` realm.

## Secrets in logs and reports

Secret attributes are marked sensitive, so their values are redacted from change notices, from
report events (and therefore from PuppetDB), and from the agent-local `last_run_report.yaml`. The
current value is reported as a fixed placeholder, `[secret managed]`, never as the stored value,
hash or ciphertext: a placeholder that varied between runs would itself read as drift.

A rotation logs as:

```
Notice: /Stage[main]/.../Pbs_user[backup@pbs]/password: password changed
```

## How PBS stores these

Two points are PBS's design rather than this module's, and worth knowing when deciding where to
keep a credential:

- `s3.cfg` holds the S3 secret key in plaintext, and `remote.cfg` holds the remote password
  base64-encoded, which is encoding, not encryption. Both files are `0640 root:backup`, so any
  member of the `backup` group can read those credentials.
- `domains.cfg` holds the OpenID `client_key` in cleartext, and the API returns it to anyone with
  realm read access.
