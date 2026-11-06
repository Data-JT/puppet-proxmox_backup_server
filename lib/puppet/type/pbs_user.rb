# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_sensitive_parameters'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pbs_user',
  docs: <<~DOC,
    @summary Manages a Proxmox Backup Server user.

    Manages user accounts via the PBS access API. Password management is only
    supported for users in the built-in `@pbs` realm and requires the Puppet
    agent to run on the PBS host itself, because password hashes are verified
    against and written to /etc/proxmox-backup/shadow.json locally.

    @example User in the pbs realm with a managed password
      pbs_user { 'john@pbs':
        ensure   => present,
        comment  => 'John Doe',
        email    => 'john@example.com',
        password => Sensitive('correct horse battery staple'),
      }

    @example Token-only user that must not log in with a password
      pbs_user { 'backup@pbs':
        ensure         => present,
        password_login => false,
      }
  DOC

  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this user should exist.',
      default: 'present',
    },
    userid: {
      type:      'Pattern[/\A[^\s@!\/]+@[A-Za-z0-9._-]+\z/]',
      desc:      'The user ID in user@realm format. The user part must not contain whitespace, "@", "!", or "/".',
      behaviour: :namevar,
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    email: {
      type: 'Optional[String]',
      desc: 'Email address of the user.',
    },
    enable: {
      type:    'Boolean',
      desc:    'Whether the user account is enabled.',
      default: true,
    },
    expire: {
      type: 'Optional[Integer]',
      desc: 'Account expiry time as a Unix timestamp (0 means no expiry).',
    },
    firstname: {
      type: 'Optional[String]',
      desc: 'First name of the user.',
    },
    lastname: {
      type: 'Optional[String]',
      desc: 'Last name of the user.',
    },
    password: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      <<~DESC,
        Write-only. Only supported for @pbs realm users, and requires the Puppet agent to run on the
        PBS host itself: it writes /etc/proxmox-backup/shadow.json locally. Set on create via the API.
        On update, written to shadow.json via yescrypt/libxcrypt. Drift is detected by verifying the
        hiera plaintext against the stored hash via crypt(3) — the password property triggers an update
        only when the stored hash no longer matches.
      DESC
      sensitive: true,
    },
    password_login: {
      type: 'Optional[Boolean]',
      desc: <<~DESC,
        Whether the user can log in with a password at all, i.e. whether shadow.json holds a hash for it.
        `false` removes the hash, and removes it again if one is ever set (e.g. in the GUI), while the
        user and its API tokens stay; use it for token-only users. Disabling the user would disable its
        tokens too. `true` requires `password`. Unset (the default) leaves it unmanaged. Only supported
        for @pbs realm users, and requires the Puppet agent to run on the PBS host itself.
        Cannot be combined with `password => ...` when `false`.
      DESC
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PBS API property names to remove during an update.',
    },
  },
)

Puppet::Type::PbsTransportAutorequire.register(:pbs_user)
Puppet::Type::PbsSensitiveParameters.register(:pbs_user)

# The @pbs-realm restriction on password management is enforced in the
# provider, NOT with a Puppet::Type.validate block here.
#
# Puppet::Type.validate is `define_method(:validate, &block)` (type.rb:2250):
# it replaces rather than chains. The Resource API installs its own validate,
# and that is where the missing-attribute list is initialised. Overwriting it
# left that ivar nil, and retrieve then calls raise_missing_attrs, which builds
# its message by joining the nil list *before* checking the guard
# (resource_api.rb:376) -- so every pbs_user resource died with
# "undefined method `join' for nil", whether or not anything was missing.
#
# Do not add a validate block to any type in this module.
