# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pbs_datastore',
  features: ['custom_insync'],
  docs: <<~DOC,
    @summary Manages a Proxmox Backup Server datastore.

    Creates and updates datastore configuration entries. Note that `path` is
    create-only: PBS does not allow moving an existing datastore, so changing
    the path of an existing datastore raises an error. Delete and recreate the
    datastore to change its location.

    @example Datastore with daily garbage collection
      pbs_datastore { 'backup':
        ensure      => present,
        path        => '/mnt/backup',
        gc_schedule => 'daily',
        comment     => 'main store',
      }
  DOC

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this datastore should exist.',
      default: 'present',
    },
    name: {
      type:      'Pattern[/\A[A-Za-z0-9_][A-Za-z0-9._-]{0,31}\z/]',
      desc:      'The datastore name (max 32 characters). Must start with an alphanumeric character or underscore, followed by alphanumerics, ".", "_", or "-".',
      behaviour: :namevar,
    },
    path: {
      type: 'String',
      desc: 'Absolute filesystem path on the PBS host. Create-only: PBS rejects path changes on existing datastores; delete and recreate the datastore to move it.',
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    gc_schedule: {
      type: 'Optional[String]',
      desc: 'Garbage collection schedule (PBS schedule string or cron format).',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PBS API property names to remove during an update.',
    },
  },
)

Puppet::Type::PbsTransportAutorequire.register(:pbs_datastore)
