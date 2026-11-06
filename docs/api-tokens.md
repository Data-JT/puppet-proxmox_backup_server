# API tokens

Examples for `pbs_api_token` and token-only users. All attributes are documented in
[REFERENCE.md](../REFERENCE.md#pbs_api_token).

The namevar is the full token ID in `user@realm!tokenname` format, the same string used to
authenticate API requests and to assign permissions via `pbs_acl`.

```puppet
pbs_user { 'automation@pbs':
  ensure         => present,
  enable         => true,
  password_login => false,
}

pbs_api_token { 'automation@pbs!ci-token':
  ensure  => present,
  comment => 'CI pipeline token',
  enable  => true,
}

pbs_acl { '/datastore/backup|automation@pbs!ci-token|DatastoreBackup':
  ensure => present,
}
```

## Token-only users

`password_login => false` keeps a token-only user from logging in with a password. PBS has no API
to remove a password, so the provider removes the user's hash from
`/etc/proxmox-backup/shadow.json` (under PBS's own lock, written atomically), and removes it again
if one is ever set later. The user itself stays enabled: disabling it would disable its tokens
too. Like `password`, it needs the agent on the PBS node as root, and it cannot be combined with a
declared `password`.

## Keeping the one-time secret

PBS returns the generated token secret only once, during creation. Set `secret_file` to retain it
on the Puppet agent with mode `0600` without exposing it in reports or logs:

```puppet
pbs_api_token { 'automation@pbs!ci-token':
  ensure      => present,
  enable      => true,
  secret_file => '/etc/puppetlabs/puppet/pbs-ci-token.secret',
}
```

The parent directory must already exist and be writable by the Puppet agent. For safety, the
destination cannot be a symbolic link. Without `secret_file`, Puppet still manages token existence
and metadata but deliberately discards the one-time secret and emits a warning.

Because PBS stores only a hash afterwards, a token secret cannot be checked for drift on later
runs.
