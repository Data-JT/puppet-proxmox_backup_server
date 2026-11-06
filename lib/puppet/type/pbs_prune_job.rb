# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:     'pbs_prune_job',
  features: ['custom_insync'],
  docs:     <<~DOC,
    @summary Manages a Proxmox Backup Server prune job.

    Prune jobs periodically remove backup snapshots from a datastore according
    to the configured keep-* retention options. Note that the schedule is set
    via `job_schedule` (not `schedule`, which is a reserved Puppet metaparameter).

    @example Daily prune keeping a week of dailies and a year of monthlies
      pbs_prune_job { 'prune-backup1-daily':
        ensure       => present,
        store        => 'backup1',
        job_schedule => 'daily',
        keep_last    => 3,
        keep_daily   => 7,
        keep_weekly  => 4,
        keep_monthly => 12,
        comment      => 'standard retention',
      }
  DOC

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this prune job should exist.',
      default: 'present',
    },
    id: {
      type:      'Pattern[/\A[A-Za-z0-9_][A-Za-z0-9._-]*\z/]',
      desc:      'Unique prune job ID. Must start with a letter, digit, or underscore and may contain only letters, digits, ".", "_", and "-".',
      behaviour: :namevar,
    },
    store: {
      type: 'String',
      desc: 'Datastore name this prune job operates on.',
    },
    job_schedule: {
      type: 'String',
      desc: <<~DESC,
        Prune schedule (PBS schedule string or cron format). Required by the PBS API.
        Maps to the PBS API field "schedule"; renamed here because "schedule" is a
        reserved Puppet metaparameter.
      DESC
    },
    ns: {
      type: 'Optional[String]',
      desc: 'Namespace within the datastore to prune.',
    },
    keep_last: {
      type: 'Optional[Integer]',
      desc: 'Keep the last N backups.',
    },
    keep_hourly: {
      type: 'Optional[Integer]',
      desc: 'Keep one backup per hour for N hours.',
    },
    keep_daily: {
      type: 'Optional[Integer]',
      desc: 'Keep one backup per day for N days.',
    },
    keep_weekly: {
      type: 'Optional[Integer]',
      desc: 'Keep one backup per week for N weeks.',
    },
    keep_monthly: {
      type: 'Optional[Integer]',
      desc: 'Keep one backup per month for N months.',
    },
    keep_yearly: {
      type: 'Optional[Integer]',
      desc: 'Keep one backup per year for N years.',
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

Puppet::Type::PbsTransportAutorequire.register(:pbs_prune_job)
