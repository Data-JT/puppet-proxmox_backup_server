# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:     'pbs_verification_job',
  features: ['custom_insync'],
  docs:     <<~DOC,
    @summary Manages a Proxmox Backup Server verification job.

    Verification jobs periodically re-check the integrity of backup snapshots in
    a datastore. Note that the schedule is set via `job_schedule` (not `schedule`,
    which is a reserved Puppet metaparameter).

    @example Weekly verification, re-verifying snapshots older than 30 days
      pbs_verification_job { 'verify-backup1-weekly':
        ensure          => present,
        store           => 'backup1',
        job_schedule    => 'sat 02:00',
        outdated_after  => 30,
        ignore_verified => true,
      }
  DOC

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this verification job should exist.',
      default: 'present',
    },
    id: {
      type:      'Pattern[/\A[A-Za-z0-9_][A-Za-z0-9._-]*\z/]',
      desc:      'Unique verification job ID. Must start with a letter, digit, or underscore and may contain only letters, digits, ".", "_", and "-".',
      behaviour: :namevar,
    },
    store: {
      type: 'String',
      desc: 'Datastore name this verification job operates on.',
    },
    job_schedule: {
      type: 'Optional[String]',
      desc: <<~DESC,
        Verification schedule (PBS schedule string or cron format).
        Maps to the PBS API field "schedule"; renamed here because "schedule" is a
        reserved Puppet metaparameter.
      DESC
    },
    outdated_after: {
      type: 'Optional[Integer]',
      desc: 'Re-verify snapshots older than N days.',
    },
    ignore_verified: {
      type:    'Boolean',
      desc:    'Skip snapshots that have already been verified.',
      default: false,
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

Puppet::Type::PbsTransportAutorequire.register(:pbs_verification_job)
