# Class parameters and TLS

The `proxmox_backup_server` class configures how the providers reach the PBS API. The generated
parameter reference is in [REFERENCE.md](../REFERENCE.md#proxmox_backup_server); this page adds
the context around it.

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `token_id` | `Pattern[/\A[^@!\s]+@[^@!\s]+![^!\s]+\z/]` | — | API token ID (`user@realm!tokenname`) |
| `token_secret` | `Sensitive[String]` | — | API token secret |
| `host` | `String` | `'localhost'` | PBS hostname or IP |
| `port` | `Integer` | `8007` | PBS API port |
| `ssl_verify` | `Boolean` | `true` | Verify the PBS TLS certificate |
| `ssl_ca_file` | `Optional[Pattern[/\A\//]]` (absolute path) | `undef` | CA bundle path (when `ssl_verify` is `true`) |
| `task_timeout` | `Optional[Integer]` | `undef` (60) | Seconds to wait for PBS background tasks |
| `config_file` | `Pattern[/\A\//]` (absolute path) | `<agent confdir>/pbs_transport.yaml` | Where to write the transport credentials |

`token_secret` must be `Sensitive`. When it comes from Hiera, convert it with `lookup_options`:

```yaml
lookup_options:
  proxmox_backup_server::token_secret:
    convert_to: Sensitive
```

In a manifest, wrap it explicitly:

```puppet
class { 'proxmox_backup_server':
  token_id     => 'puppet@pbs!puppet-token',
  token_secret => Sensitive(lookup('pbs::token_secret')),
}
```

## TLS verification

TLS verification is enabled by default. A fresh PBS installation serves a self-signed certificate
that fails verification, so either point `ssl_ca_file` at the CA certificate that signed the PBS
certificate (recommended), or explicitly set `ssl_verify => false`. Disabling verification allows
man-in-the-middle attacks on the API connection; it is only a reasonable trade-off when the API
traffic never leaves the node (`host => 'localhost'`, the default).

## The transport file

The class writes the credentials to `config_file` (mode `0600`, `root:root`), which the providers
read at agent run time. Declare the class on every PBS node, in `site.pp`, a role or a profile.

- All `pbs_*` types automatically require the managed transport file when it is present in the
  catalog. On a first run, providers wait for that file and refresh actual PBS state before
  creating or updating resources, so a single `puppet agent -t` applies the class and all
  `pbs_*` resources in the same pass.
- When `config_file` points elsewhere, the class creates a symlink at the provider discovery path
  (`<agent confdir>/pbs_transport.yaml`).
- The default is the agent's own confdir (from the `proxmox_backup_server_confdir` fact), not the
  compiling server's, since the two can differ.
