# Authentication realms

Examples for `pbs_realm`, which manages external authentication realms. All attributes are
documented in [REFERENCE.md](../REFERENCE.md#pbs_realm).

The `type` attribute selects the backend and routes to the corresponding PBS API endpoint
(`/config/access/{type}`). It cannot be changed after creation: to switch types, set
`ensure => absent` and re-create the realm.

## LDAP

```puppet
pbs_realm { 'corp-ldap':
  ensure        => present,
  type          => 'ldap',
  server1       => 'ldap.example.com',
  server2       => 'ldap2.example.com',
  base_dn       => 'dc=example,dc=com',
  user_attr     => 'uid',
  bind_dn       => 'cn=search,dc=example,dc=com',
  bind_password => Sensitive(lookup('pbs::ldap_bind_password')),
  mode          => 'ldap+starttls',
  verify        => true,
  comment       => 'Corporate LDAP',
}
```

## Active Directory

```puppet
pbs_realm { 'corp-ad':
  ensure        => present,
  type          => 'ad',
  server1       => 'ad.example.com',
  base_dn       => 'dc=example,dc=com',
  bind_dn       => 'cn=search,dc=example,dc=com',
  bind_password => Sensitive(lookup('pbs::ad_bind_password')),
  mode          => 'ldaps',
  verify        => true,
}
```

## OpenID Connect

```puppet
pbs_realm { 'sso':
  ensure         => present,
  type           => 'openid',
  issuer_url     => 'https://sso.example.com',
  client_id      => 'proxmox-backup',
  client_key     => Sensitive(lookup('pbs::oidc_client_secret')),
  username_claim => 'email',
  autocreate     => true,
  scopes         => 'openid email profile',
  default        => true,
  comment        => 'Corporate SSO',
}
```

## Realm credentials

Both realm credentials are fully enforced, by different means:

- `bind_password` (LDAP/AD) is never returned by the API. Drift is detected against
  `/etc/proxmox-backup/ldap_passwords.json`, which PBS keeps in plaintext, mode `0600 root:root`,
  keyed by realm name and shared by `ldap` and `ad` realms.
- `client_key` (OpenID) is returned by the API, verbatim. It needs no on-node access at all and is
  compared like any ordinary property. PBS stores it in cleartext in
  `/etc/proxmox-backup/domains.cfg` and hands it back to anyone with realm read access; that is
  PBS's design, not this module's.

Changing either value in Hiera rotates it on the next run. See
[Secret drift detection](secret-drift.md).
