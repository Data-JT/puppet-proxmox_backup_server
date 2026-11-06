# Importing an existing node into Hiera

How to adopt a PBS node that is already configured, by generating Hiera data from its live API.

`tools/pbs_hiera_import.rb` generates Hiera data for the `proxmox_backup_server::resources` class
from the live PBS API, so Puppet can adopt resources that already exist. It is a checkout-only
utility and is intentionally not included in the Puppet Forge package. It verifies TLS
certificates by default; use `--no-ssl-verify` only on a trusted network when verification cannot
be configured.

## Running the import

First make sure the API token can read the resource types you want to import.

```sh
ruby tools/pbs_hiera_import.rb \
  --host localhost \
  --token-id 'puppet@pbs!puppet-token' \
  --token-secret-file /root/pbs-token.secret \
  --output pbs-import.yaml
```

`--token-secret` is also accepted, but passing a secret on the command line exposes it in your
shell history and in process listings (`ps`). If the `proxmox_backup_server` class has already
written `<agent confdir>/pbs_transport.yaml` (`/etc/puppetlabs/puppet` on AIO agents) on the PBS
node, you can reuse that transport file instead:

```sh
ruby tools/pbs_hiera_import.rb \
  --transport-config /etc/puppetlabs/puppet/pbs_transport.yaml \
  --output pbs-import.yaml
```

Run `ruby tools/pbs_hiera_import.rb --help` for further options, such as `--skip-errors` and
`--include-transport-parameters`.

## Adopting the data

Add the generated data to the node's Hiera hierarchy and include `proxmox_backup_server::resources`
together with the main class. Run the first adoption pass in no-op mode and review the proposed
changes before applying normally:

```sh
puppet agent -t --noop
```

Existing PBS resources that are absent from the Hiera data are not purged by this module.

## Remote passwords

Remote passwords are not returned by the PBS API, so imported `pbs_remote` entries contain no
`password` key. An existing remote keeps its password and Puppet leaves it unmanaged. To manage
it, add the real secret (encrypted): it is then drift-checked against `remote.cfg` (see
[Secret drift detection](secret-drift.md)). A remote recreated on a new node needs the `password`
key, because PBS cannot create one without it. `--remote-password-placeholder VALUE` writes VALUE
into each entry as a marker; replace it before the first non-noop run, or Puppet writes it to PBS.
