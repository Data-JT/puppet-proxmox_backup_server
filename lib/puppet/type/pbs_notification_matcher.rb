# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:  'pbs_notification_matcher',
  features: ['custom_insync'],
  docs:  <<~DOC,
    @summary Manages a Proxmox Backup Server notification matcher (routing rule).

    Matchers route notifications to one or more notification targets based on
    severity, calendar, and metadata field match rules. See `pbs_notification_target`
    for managing the targets themselves.

    @example Route errors and warnings to an SMTP target during business hours
      pbs_notification_matcher { 'business-hours-errors':
        ensure         => present,
        target         => ['smtp-relay'],
        match_severity => ['error', 'warning'],
        match_calendar => ['mon-fri 09:00-17:00'],
        mode           => 'all',
        comment        => 'notify ops during business hours',
      }
  DOC

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this notification matcher should exist.',
      default: 'present',
    },
    name: {
      type:      'Pattern[/\A[A-Za-z0-9_][A-Za-z0-9._-]*\z/]',
      desc:      'The matcher name. Must start with a letter, digit, or underscore and may contain only letters, digits, ".", "_", and "-".',
      behaviour: :namevar,
    },
    target: {
      type: 'Optional[Array[String]]',
      desc: 'Notification target names this matcher routes matched notifications to.',
    },
    match_severity: {
      type: 'Optional[Array[String]]',
      desc: 'Severity levels to match. Valid values: info, notice, warning, error, unknown.',
    },
    match_calendar: {
      type: 'Optional[Array[String]]',
      desc: 'Calendar schedule expressions to match (e.g. "mon-fri 09:00-17:00").',
    },
    match_field: {
      type: 'Optional[Array[String]]',
      desc: 'Metadata field matchers (e.g. "exact:type=gc", "regex:datastore=^backup-.*$").',
    },
    mode: {
      type:    'Optional[Enum[all, any]]',
      desc:    'Whether all (AND) or any (OR) match rules must be satisfied. Defaults to all.',
    },
    invert_match: {
      type: 'Optional[Boolean]',
      desc: 'Invert the overall match result.',
    },
    disable: {
      type: 'Optional[Boolean]',
      desc: 'Disable this matcher.',
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

Puppet::Type::PbsTransportAutorequire.register(:pbs_notification_matcher)
