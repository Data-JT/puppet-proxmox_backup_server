# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pbs_node_config',
  docs: <<~DOC,
    @summary Manages PBS node-level configuration, including the Notes section visible in the web UI.

    This resource is only meaningful for the local node: the resource title
    must be the short hostname of the PBS host the transport talks to, and the
    provider raises an error otherwise. The node configuration always exists
    and cannot be deleted, so `ensure => absent` raises an error as well — to
    stop managing these settings, simply remove the resource from the manifest.

    @example Manage the node Notes and notification sender
      pbs_node_config { 'pbs':
        description => "# My PBS Server\\n\\nManaged by Puppet.",
        email_from  => 'pbs@example.com',
      }
  DOC

  features: ['canonicalize', 'custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Present keeps the configuration in sync. Absent raises an error (the node config always exists and cannot be deleted); remove the resource from the manifest to stop managing it.',
      default: 'present',
    },
    node: {
      type:      'Pattern[/\A[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\z/]',
      desc:      'PBS node name as returned by GET /nodes (the short hostname, e.g. "pbs"). Must be the short hostname of the local node.',
      behaviour: :namevar,
    },
    description: {
      type: 'Optional[String]',
      desc: 'Free-form text shown in the Notes panel of the PBS web UI (supports Markdown). A single trailing newline is ignored when comparing state, since PBS strips it.',
    },
    email_from: {
      type: 'Optional[String]',
      desc: 'Sender email address used by PBS for outgoing notification emails.',
    },
    http_proxy: {
      type: 'Optional[String]',
      desc: 'HTTP proxy used by PBS for outbound connections (e.g. https://proxy.example.com:3128).',
    },
    default_lang: {
      type: 'Optional[String]',
      desc: 'Default web UI language (e.g. "en", "de").',
    },
    task_log_max_days: {
      type: 'Optional[Integer]',
      desc: 'Number of days to keep finished task logs.',
    },
    consent_text: {
      type: 'Optional[String]',
      desc: 'Text shown on the login screen as a consent or banner message.',
    },
    location: {
      type: 'Optional[String]',
      desc: 'Physical or logical location label for this PBS node.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PBS API property names to remove during an update.',
    },
  },
)

Puppet::Type::PbsTransportAutorequire.register(:pbs_node_config)
