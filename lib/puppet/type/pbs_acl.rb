# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:     'pbs_acl',
  docs:     <<~DOC,
    @summary Manages a Proxmox Backup Server ACL entry.

    The resource title is a composite of the three namevars joined by pipes:
    `<acl_path>|<ugid>|<role>`, where

    * `acl_path` is the object path the ACL applies to (e.g. `/` or `/datastore/backup1`),
    * `ugid` is the user ID (`user@realm`) or API token authid (`user@realm!tokenname`)
      the ACL grants access to, and
    * `role` is the PBS role to assign (e.g. `DatastoreBackup`).

    Alternatively, provide only the path as the title and set `ugid` and `role`
    as explicit attributes.

    @example Grant a user backup access to a datastore
      pbs_acl { '/datastore/backup1|user@pbs|DatastoreBackup':
        ensure => present,
      }

    @example Grant an API token audit access to everything, without propagation
      pbs_acl { '/|automation@pbs!ci|Audit':
        ensure    => present,
        propagate => false,
      }
  DOC

  title_patterns: [
    {
      pattern: %r{^(?<acl_path>[^|]+)\|(?<ugid>[^|]+)\|(?<role>[^|]+)$},
      desc:    'Where acl_path, ugid and role are provided with pipe separators',
    },
    {
      pattern: %r{^(?<acl_path>.*)$},
      desc:    'Where only the acl_path is provided (requires ugid and role params)',
    },
  ],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this ACL entry should exist.',
      default: 'present',
    },
    acl_path: {
      type:      'Pattern[/\A\/[A-Za-z0-9._\-\/]*\z/]',
      desc:      'The ACL path (e.g. /, /datastore/local). Must start with "/" and may contain only letters, digits, ".", "_", "-", and "/".',
      behaviour: :namevar,
    },
    ugid: {
      type:      'Pattern[/\A[^\s@!\/|]+@[A-Za-z0-9._-]+(?:![A-Za-z0-9._-]+)?\z/]',
      desc:      'The user ID (user@realm) or API token authid (user@realm!tokenname) this ACL applies to.',
      behaviour: :namevar,
    },
    role: {
      type:      "Enum['Admin', 'Audit', 'NoAccess', 'DatastoreAdmin', 'DatastoreReader', 'DatastoreBackup',
                      'DatastorePowerUser', 'DatastoreAudit', 'RemoteAudit', 'RemoteAdmin',
                      'RemoteSyncOperator', 'RemoteSyncPushOperator', 'RemoteDatastorePowerUser',
                      'RemoteDatastoreAdmin', 'TapeAudit', 'TapeAdmin', 'TapeOperator', 'TapeReader']",
      desc:      'The role to assign.',
      behaviour: :namevar,
    },
    propagate: {
      type:    'Boolean',
      desc:    'Whether the ACL entry propagates to sub-paths.',
      default: true,
    },
  },
)

Puppet::Type::PbsTransportAutorequire.register(:pbs_acl)
