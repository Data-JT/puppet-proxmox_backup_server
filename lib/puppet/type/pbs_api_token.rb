# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:  'pbs_api_token',
  features: ['custom_insync'],
  docs:  <<~DOC,
    @summary Manages a Proxmox Backup Server API token.

    PBS returns a generated token secret only during creation. Set `secret_file` to
    retain it on the Puppet agent without exposing it in reports or logs.

    @example Create a token and retain its generated secret
      pbs_api_token { 'automation@pbs!ci':
        ensure      => present,
        enable      => true,
        comment     => 'CI automation',
        secret_file => '/etc/puppetlabs/puppet/pbs-ci-token.secret',
      }
  DOC

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this API token should exist.',
      default: 'present',
    },
    tokenid: {
      type:      'Pattern[/\A[^\s@!\/]+@[A-Za-z0-9._-]+![A-Za-z0-9._-]+\z/]',
      desc:      'Full token ID in user@realm!tokenname format (e.g. automation@pbs!ci). The realm and token name may contain only letters, digits, ".", "_", and "-".',
      behaviour: :namevar,
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    enable: {
      type: 'Optional[Boolean]',
      desc: 'Whether the token is enabled.',
    },
    expire: {
      type: 'Optional[Integer]',
      desc: 'Expiry as a Unix timestamp. 0 or unset means no expiry.',
    },
    secret_file: {
      type: 'Optional[String]',
      behaviour: :parameter,
      desc: 'Agent-local file receiving the one-time token secret on creation, written with mode 0600.',
    },
    delete_properties: {
      type: "Optional[Array[Enum['comment']]]",
      desc: 'PBS API property names to remove during an update. Only `comment` can be removed. Requires PBS 3.4 or later; older releases reject the parameter.',
    },
  },
)

Puppet::Type::PbsTransportAutorequire.register(:pbs_api_token)
