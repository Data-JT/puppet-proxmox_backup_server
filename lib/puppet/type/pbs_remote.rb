# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_sensitive_parameters'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pbs_remote',
  docs: <<~DOC,
    @summary Manages a Proxmox Backup Server remote.

    Remotes are other PBS instances that sync jobs can pull from or push to.

    The `password` is enforced. PBS never returns it over the API, so drift is
    detected against the base64-encoded copy in /etc/proxmox-backup/remote.cfg,
    which requires the Puppet agent to run on the PBS node as root. Changing
    the password in the manifest rotates it on the next run; leaving it
    unchanged sends nothing at all.

    @example Remote authenticated with an API token
      pbs_remote { 'offsite-pbs':
        ensure      => present,
        host        => 'pbs.example.com',
        userid      => 'sync@pbs!puppet',
        password    => Sensitive('token-secret'),
        fingerprint => 'AA:BB:CC:...',
      }
  DOC

  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this remote should exist.',
      default: 'present',
    },
    name: {
      type:      'Pattern[/\A[A-Za-z0-9_][A-Za-z0-9._-]*\z/]',
      desc:      'The remote name. Must start with an alphanumeric character or underscore, followed by alphanumerics, ".", "_", or "-".',
      behaviour: :namevar,
    },
    host: {
      type: 'String',
      desc: 'Hostname or IP of the remote PBS server.',
    },
    port: {
      type: 'Optional[Integer]',
      desc: 'Port of the remote PBS API (default: 8007).',
    },
    userid: {
      type: 'String',
      desc: 'The auth ID for authenticating to the remote PBS: a user ID (user@realm) or an API token ID (user@realm!tokenname). Maps to the PBS API field "auth-id".',
    },
    password: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      <<~DESC,
        Password or token secret for the remote. PBS never returns it, so drift is detected against the
        base64-encoded copy in /etc/proxmox-backup/remote.cfg, which requires the Puppet agent to run
        on the PBS node as root. Sent only when it differs from the stored value. Not required when
        ensure => absent.
      DESC
      sensitive: true,
    },
    fingerprint: {
      type: 'Optional[String]',
      desc: 'TLS certificate fingerprint of the remote PBS server.',
    },
    use_node_proxy: {
      type: 'Optional[Boolean]',
      desc: 'Whether to use the local node proxy for connections to the remote.',
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PBS API property names to remove during an update.',
    },
  },
)

Puppet::Type::PbsTransportAutorequire.register(:pbs_remote)
Puppet::Type::PbsSensitiveParameters.register(:pbs_remote)
