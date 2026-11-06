# Notifications

Examples for `pbs_notification_target` (delivery endpoints) and `pbs_notification_matcher`
(routing rules), available on PBS 3.x and later. All attributes are documented in
[REFERENCE.md](../REFERENCE.md#pbs_notification_target).

The `type` of a target cannot be changed after creation. To switch types, set `ensure => absent`
and re-create the resource with the new type.

## Sendmail target

```puppet
pbs_notification_target { 'mail-admins':
  ensure       => present,
  type         => 'sendmail',
  mailto       => ['ops@example.com'],
  from_address => 'pbs@example.com',
}
```

## SMTP target

```puppet
pbs_notification_target { 'smtp-relay':
  ensure        => present,
  type          => 'smtp',
  server        => 'smtp.example.com',
  port          => 587,
  mode          => 'starttls',
  username      => 'pbs',
  smtp_password => Sensitive(lookup('pbs::smtp_password')),
  from_address  => 'pbs@example.com',
  mailto        => ['ops@example.com'],
}
```

## Gotify target

```puppet
pbs_notification_target { 'gotify-push':
  ensure => present,
  type   => 'gotify',
  server => 'https://gotify.example.com',
  token  => Sensitive(lookup('pbs::gotify_token')),
}
```

## Webhook target

```puppet
pbs_notification_target { 'webhook-ops':
  ensure      => present,
  type        => 'webhook',
  url         => 'https://hooks.example.com/notify',
  http_method => 'post',
  body        => '{"text": "{{subject}}"}',
  # PBS requires values to be base64-encoded. This is "application/json".
  header      => [{ 'name' => 'Content-Type', 'value' => 'YXBwbGljYXRpb24vanNvbg==' }],
  secret      => [{ 'name' => 'token', 'value' => lookup('pbs::webhook_token_base64') }],
}
```

Store the webhook secret in Hiera as a base64-encoded value as well. PBS expects the `value` field
for both `header` and `secret` in that format.

## Matcher

```puppet
pbs_notification_matcher { 'errors-to-ops':
  ensure         => present,
  target         => ['smtp-relay', 'gotify-push'],
  match_severity => ['error', 'warning'],
  mode           => 'any',
  comment        => 'Route errors and warnings to ops',
}
```

## Hiera

The same objects, declared through `proxmox_backup_server::resources`:

```yaml
proxmox_backup_server::resources::notification_targets:
  mail-ops:
    type: sendmail
    mailto: [ops@example.com]

proxmox_backup_server::resources::notification_matchers:
  errors-to-ops:
    target: [mail-ops]
    match_severity: [error, warning]
```

## Target credentials

`smtp_password`, `token` (gotify) and `secret` (webhook) are all enforced. PBS never returns them
over the API (for a webhook it returns each secret's name with the value stripped), so drift is
detected against `/etc/proxmox-backup/notifications-priv.cfg`, a separate `0600 root:root` file
from the public `notifications.cfg`.

Changing any of them in Hiera rotates it on the next run. A webhook `secret` entry given without a
`value` means "keep whatever PBS already stores", which is how PBS itself expresses an unchanged
secret. See [Secret drift detection](secret-drift.md).
