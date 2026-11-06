# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pbs_sync_job',
  features: ['custom_insync'],
  docs: <<~DOC,
    @summary Manages a Proxmox Backup Server sync job.

    Sync jobs transfer backup groups between datastores, either pulling from
    (or pushing to) a configured remote, or locally between datastores on the
    same PBS instance.

    Note: the PBS API field `schedule` is exposed here as `job_schedule`,
    because `schedule` is a reserved Puppet metaparameter and cannot be used
    as an attribute name.

    @example Nightly pull sync from a remote PBS
      pbs_sync_job { 'nightly-offsite':
        ensure       => present,
        store        => 'local',
        remote       => 'offsite-pbs',
        remote_store => 'backup',
        job_schedule => 'daily',
        group_filter => ['type:vm', 'group:vm/100'],
      }
  DOC

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this sync job should exist.',
      default: 'present',
    },
    id: {
      type:      'Pattern[/\A[A-Za-z0-9_][A-Za-z0-9._-]*\z/]',
      desc:      'Unique sync job ID. Must start with an alphanumeric character or underscore, followed by alphanumerics, ".", "_", or "-".',
      behaviour: :namevar,
    },
    store: {
      type: 'String',
      desc: 'Local datastore name to sync into.',
    },
    remote: {
      type: 'Optional[String]',
      desc: 'Name of the remote configured on this PBS. Omit for local (remote-less) sync jobs.',
    },
    remote_store: {
      type: 'String',
      desc: 'Datastore name on the remote PBS.',
    },
    job_schedule: {
      type: 'Optional[String]',
      desc: 'Sync schedule (PBS schedule string or cron format). Maps to the PBS API field "schedule", renamed because schedule is a Puppet metaparameter.',
    },
    remote_ns: {
      type: 'Optional[String]',
      desc: 'Namespace on the remote datastore to sync from.',
    },
    ns: {
      type: 'Optional[String]',
      desc: 'Local namespace to sync into.',
    },
    max_depth: {
      type: 'Optional[Integer]',
      desc: 'Maximum namespace recursion depth (0 = no recursion).',
    },
    sync_direction: {
      type: "Optional[Enum['pull', 'push']]",
      desc: 'Direction of the sync job. Defaults to pull when omitted.',
    },
    owner: {
      type: 'Optional[String]',
      desc: 'Auth ID that owns this sync job.',
    },
    group_filter: {
      type: 'Optional[Array[String]]',
      desc: "List of backup group filter expressions; only matching groups are synced (e.g. ['type:vm', 'group:vm/100']).",
    },
    remove_vanished: {
      type:    'Boolean',
      desc:    'Remove snapshots that no longer exist on the source.',
      default: false,
    },
    transfer_last: {
      type: 'Optional[Integer]',
      desc: 'Transfer only the last N snapshots per group.',
    },
    resync_corrupt: {
      type: 'Optional[Boolean]',
      desc: 'Re-sync corrupted snapshots (pull jobs only).',
    },
    encrypted_only: {
      type: 'Optional[Boolean]',
      desc: 'Skip unencrypted backups during sync.',
    },
    verified_only: {
      type: 'Optional[Boolean]',
      desc: 'Skip unverified snapshots during sync.',
    },
    rate_in: {
      type: 'Optional[String]',
      desc: 'Inbound bandwidth limit for pull jobs as a HumanByte string (e.g. "8 MiB") or a plain byte count string.',
    },
    worker_threads: {
      type: 'Optional[Integer]',
      desc: 'Number of parallel transfer threads.',
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

Puppet::Type::PbsTransportAutorequire.register(:pbs_sync_job)
