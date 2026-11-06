<a href="https://www.data-jt.de">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Data-JT/.github/main/profile/banner-dark.svg">
    <img alt="Data JT" src="https://raw.githubusercontent.com/Data-JT/.github/main/profile/banner-light.svg" width="420">
  </picture>
</a>

# datajt-proxmox_backup_server

Manage Proxmox Backup Server configuration as Puppet code, through the PBS REST API.

## Table of contents

1. [Description](#description)
2. [Requirements](#requirements)
3. [Quick start](#quick-start)
4. [Resource types](#resource-types)
5. [Further documentation](#further-documentation)
6. [Limitations](#limitations)
7. [Contributing](#contributing)
8. [License](#license)
9. [About Data JT](#about-data-jt)

## Description

This module lets you describe the configuration of a [Proxmox Backup Server](https://www.proxmox.com/en/proxmox-backup-server)
(PBS) node in Puppet code or Hiera: datastores, users, permissions, sync, prune and verification
jobs, authentication realms, notifications and more. The Puppet agent on the PBS node compares
that description with the live configuration and changes only what differs.

### What it does

- Manages 13 kinds of PBS objects as native Puppet resource types (`pbs_*`).
- Declares all of them from Hiera through one class, `proxmox_backup_server::resources`.
- Detects and enforces drift in secrets (remote passwords, LDAP bind passwords, S3 keys,
  notification credentials, user passwords), and keeps them out of logs and reports.
- Ships a Bolt task for ad-hoc API calls and a checkout-only utility that imports an existing
  node into Hiera data.

### What it does not do

- It does not install PBS, manage its apt repository or its services. It configures an existing PBS.
- It does not use `puppet device`, a proxy agent or a Bolt transport. The agent runs on the PBS node.
- It does not purge PBS objects that are not declared in Puppet.
- It does not clear a value when you remove an attribute; use `delete_properties` for that.
- It cannot verify API token secrets after creation: PBS keeps only a hash.
- It talks only to the REST API, with one exception: `pbs_user` passwords are written to
  `/etc/proxmox-backup/shadow.json`, because the API cannot set them without the current password.

### How it works

```text
Hiera / manifest              declares the class and the resources
      │
      ▼
proxmox_backup_server class   writes pbs_transport.yaml (token, 0600)
      │
      ▼
pbs_* types                   read that file on every agent run on the PBS node
      │
      ▼
PBS REST API                  https://localhost:8007
```

The `proxmox_backup_server` class writes the API token and connection settings to a transport
file in the agent's confdir. The `pbs_*` types are built on the Puppet Resource API; their
providers read that file and call the local PBS API on every agent run. Resources come from
manifests or from Hiera via `proxmox_backup_server::resources`. Secrets PBS does not
return over the API are compared against PBS's own files under `/etc/proxmox-backup/`, which is
why the agent runs as root on the node.

## Requirements

- Puppet or OpenVox 8 or 9 (`>= 8.0.0 < 10.0.0`). Testing is currently done on 8 (CI and production); on 9 the unit tests also run in CI
  (OpenVox 9.3), but there is no production use yet. No Forge dependencies; the Resource API ships with Puppet.
- Debian 12 (PBS 3.x) or Debian 13 (PBS 4.x). Tested against PBS 4.2.1.
- The Puppet agent running as root on the PBS node.
- A PBS API token with the permissions for the objects you manage.
- `libcrypt.so.1` (libxcrypt) on the node, present on every PBS installation.

## Quick start

### 1. Prepare PBS

Create a dedicated user and API token, and grant the token the permissions it needs:

```sh
proxmox-backup-manager user create puppet@pbs
proxmox-backup-manager user generate-token puppet@pbs puppet-token   # prints the secret once
proxmox-backup-manager acl update / Admin --auth-id puppet@pbs
proxmox-backup-manager acl update / Admin --auth-id 'puppet@pbs!puppet-token'
```

A token never has more rights than its user, so both need the ACL. `Admin` on `/` covers every
resource type; narrow the path and role (for example `DatastoreAdmin` on `/datastore`) if you
manage only a subset.

### 2. Manifest

```puppet
# site/profile/manifests/backup_server.pp
class profile::backup_server {
  include proxmox_backup_server            # transport: token_id, token_secret from Hiera
  include proxmox_backup_server::resources # pbs_* resources from Hiera

  # Resources can also be declared directly:
  pbs_node_config { $facts['networking']['hostname']:
    email_from        => 'pbs@example.com',
    task_log_max_days => 30,
  }
}
```

### 3. Hiera

```yaml
# Class parameters. Keep the secret encrypted (hiera-eyaml) and convert it to Sensitive.
lookup_options:
  proxmox_backup_server::token_secret:
    convert_to: Sensitive

proxmox_backup_server::token_id: 'puppet@pbs!puppet-token'
proxmox_backup_server::token_secret: ENC[PKCS7,...]
proxmox_backup_server::ssl_ca_file: /etc/ssl/certs/example-ca.pem  # or ssl_verify: false on localhost

# Resources
proxmox_backup_server::resources::datastores:
  backup:
    path: /mnt/datastore/backup
    gc_schedule: daily
  offsite:
    path: /mnt/datastore/offsite

proxmox_backup_server::resources::users:
  backup@pbs:
    firstname: Backup
    lastname: Service
    password_login: false

proxmox_backup_server::resources::acls:
  '/datastore/backup|backup@pbs|DatastoreBackup': {}

proxmox_backup_server::resources::remotes:
  primary:
    host: pbs-primary.example.com
    userid: 'sync@pbs!replication'
    password: ENC[PKCS7,...]
    fingerprint: 'AA:BB:CC:...'

proxmox_backup_server::resources::sync_jobs:
  pull-primary:
    store: offsite
    remote: primary
    remote_store: backup
    job_schedule: hourly

proxmox_backup_server::resources::prune_jobs:
  prune-backup:
    store: backup
    job_schedule: daily
    keep_daily: 7
    keep_weekly: 4

proxmox_backup_server::resources::verification_jobs:
  verify-backup:
    store: backup
    job_schedule: weekly
    ignore_verified: true
    outdated_after: 30
```

`ensure` defaults to `present`. The resources class orders related entries it declares itself
(realms, users, tokens, ACLs, datastores, remotes, jobs, notification targets and matchers).
Realms, notifications and S3 endpoints work the same way; see the docs pages below. Run the
first pass with `puppet agent -t --noop`.

## Resource types

| Type | Manages |
|---|---|
| `pbs_datastore` | Datastores (path, garbage collection schedule) |
| `pbs_user` | Users, including `@pbs` passwords and password login |
| `pbs_api_token` | API tokens of a user |
| `pbs_acl` | ACL entries (`path\|user-or-token\|role`) |
| `pbs_realm` | LDAP, Active Directory and OpenID Connect realms |
| `pbs_remote` | Remote PBS servers |
| `pbs_sync_job` | Pull and push sync jobs |
| `pbs_prune_job` | Prune jobs and retention |
| `pbs_verification_job` | Verification jobs |
| `pbs_notification_target` | Notification targets (sendmail, smtp, gotify, webhook) |
| `pbs_notification_matcher` | Notification routing rules |
| `pbs_s3_endpoint` | S3 endpoints |
| `pbs_node_config` | Node settings (notes, email sender, proxy, task log retention) |

Every attribute, the class parameters and the `pbs_api_request` task are documented in
[REFERENCE.md](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/REFERENCE.md).

## Further documentation

- [Class parameters and TLS](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/docs/class-parameters.md): transport settings, certificate verification, the transport file.
- [Secret drift detection](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/docs/secret-drift.md): how secrets are compared and redacted, and why user passwords go to `shadow.json`.
- [Clearing optional properties](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/docs/clearing-properties.md): removing a value on the PBS side with `delete_properties`.
- [Authentication realms](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/docs/realms.md): LDAP, AD and OpenID examples and their credentials.
- [API tokens](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/docs/api-tokens.md): token-only users and keeping the one-time secret.
- [Notifications](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/docs/notifications.md): target types, matchers and their credentials.
- [Importing an existing node](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/docs/hiera-import.md): generate Hiera data from a live PBS.
- [Ad-hoc API access](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/docs/api-access.md): the `pbs_api_request` Bolt task.

## Limitations

- Managing any secret, and `pbs_node_config`, requires the agent on the PBS node as root. If a
  secret's store cannot be read, the run fails rather than reporting the resource in sync.
- `pbs_user` passwords can be managed only for users in the `@pbs` realm.
- `pbs_node_config` must be titled with the node's short hostname.
- The `type` of a realm or notification target cannot be changed; remove and re-create it.

## Contributing

Issues and pull requests are welcome on
[GitHub](https://github.com/Data-JT/puppet-proxmox_backup_server/issues); please open an issue
before significant work. See [CONTRIBUTING.md](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/CONTRIBUTING.md)
for the development workflow and [SECURITY.md](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/SECURITY.md)
for reporting vulnerabilities.

## License

Apache-2.0, see [LICENSE](https://github.com/Data-JT/puppet-proxmox_backup_server/blob/master/LICENSE).

## About Data JT

This module is built and maintained by [Data JT](https://www.data-jt.de), an IT and data
protection consultancy near Freiburg, Germany. All our modules are on the
[Puppet Forge](https://forge.puppet.com/modules/datajt). For anything beyond issues and pull
requests, [get in touch](https://www.data-jt.de/kontakt).
