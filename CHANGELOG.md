# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `tools/pbs_hiera_import.rb` no longer writes a placeholder as the `password` of imported
  remotes, which Puppet would have sent to PBS if it was not replaced. The key is omitted, and
  `--remote-password-placeholder` still adds a marker on request.

### Changed

- The Quality workflow also runs the unit tests on OpenVox 9.
- Data JT banner and an About section in the README; `metadata.json` names Data JT as the
  author.

## [0.1.0] - 2026-11-06

Initial release.

### Added

- Supports Puppet 8 and 9 (tested on 8) on Debian 12 (PBS 3.x) and Debian 13 (PBS 4.x). The
  module has no Forge dependencies; the Resource API it builds on ships with Puppet.
- `proxmox_backup_server` class that writes the API transport credentials to a
  `root:root` mode `0600` file, with the parameters `token_id`, `token_secret`, `host`,
  `port`, `ssl_verify`, `ssl_ca_file`, `task_timeout` and `config_file`. TLS certificates
  are verified by default. When `config_file` points elsewhere, a symlink is created at
  the provider discovery path.
- The transport file and its provider discovery path follow the agent's own Puppet
  confdir (fact `proxmox_backup_server_confdir`), not the compiling server's, so an
  OpenVox/AIO server can compile for a Debian-packaged agent.
- `task_timeout` bounds the wait for PBS background tasks and defaults to 60 seconds. API
  requests time out after 10 seconds connecting and 60 seconds reading.
- `proxmox_backup_server::resources` class that declares resources from Hiera hashes and
  orders related entries declared through it.
- Resource types: `pbs_acl`, `pbs_api_token`, `pbs_datastore`, `pbs_node_config`,
  `pbs_notification_matcher`, `pbs_notification_target`, `pbs_prune_job`, `pbs_realm`,
  `pbs_remote`, `pbs_s3_endpoint`, `pbs_sync_job`, `pbs_user` and `pbs_verification_job`.
- Drift detection and enforcement for every managed secret: changing a secret in Hiera
  rotates it on the next run. Secrets are compared against PBS's own copies in
  `ldap_passwords.json`, `remote.cfg`, `s3.cfg`, `notifications-priv.cfg` and
  `shadow.json`, which requires the agent to run on the PBS node as root; a declared
  secret whose store cannot be read fails the run. The OpenID `client_key` is compared
  over the API. A secret is sent to PBS only when it differs from the stored copy.
- `pbs_user` passwords are written to `/etc/proxmox-backup/shadow.json` as a yescrypt hash,
  under PBS's own lock. This is the only change the module makes outside the REST API.
- `pbs_user` `password_login => false` removes, and keeps removed, a `@pbs` user's password
  hash, so token-only users cannot log in with a password.
- Secret attributes are redacted from change notices, report events, PuppetDB and
  `last_run_report.yaml`.
- `delete_properties` clears optional properties on every type except `pbs_acl`:
  `pbs_api_token`, `pbs_datastore`, `pbs_node_config`, `pbs_notification_matcher`,
  `pbs_notification_target`, `pbs_prune_job`, `pbs_realm`, `pbs_remote`,
  `pbs_s3_endpoint`, `pbs_sync_job`, `pbs_user` and `pbs_verification_job`. On
  `pbs_api_token` it accepts only `comment` and requires PBS 3.4 or later.
- Optional `secret_file` on `pbs_api_token` retains the one-time token secret on the agent
  with mode `0600`.
- `pbs_api_request` task for ad-hoc API calls.
- `tools/pbs_hiera_import.rb`, a checkout-only tool that generates Hiera data from an
  existing PBS instance. It is not part of the Forge package.

[Unreleased]: https://github.com/Data-JT/puppet-proxmox_backup_server/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Data-JT/puppet-proxmox_backup_server/releases/tag/v0.1.0
