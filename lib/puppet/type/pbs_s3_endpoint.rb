# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_sensitive_parameters'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pbs_s3_endpoint',
  docs: <<~DOC,
    @summary Manages a Proxmox Backup Server S3 client endpoint configuration.

    Configures S3-compatible object storage endpoints under /config/s3.

    The `secret_key` is required when creating an endpoint and is enforced
    thereafter. PBS never returns it over the API, so drift is detected against
    the plaintext copy in /etc/proxmox-backup/s3.cfg, which requires the Puppet
    agent to run on the PBS node as root. Changing it in the manifest rotates
    it on the next run.

    @example Endpoint for an S3-compatible object store
      pbs_s3_endpoint { 'minio-local':
        ensure     => present,
        endpoint   => 'https://minio.example.com',
        access_key => 'AKIAIOSFODNN7EXAMPLE',
        secret_key => Sensitive('wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'),
        path_style => true,
      }
  DOC

  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this S3 endpoint should exist.',
      default: 'present',
    },
    id: {
      type:      'Pattern[/\A[A-Za-z0-9_][A-Za-z0-9._-]*\z/]',
      desc:      'Unique S3 endpoint identifier. Must start with an alphanumeric character or underscore, followed by alphanumerics, ".", "_", or "-".',
      behaviour: :namevar,
    },
    endpoint: {
      type: 'String',
      desc: 'S3 server endpoint URL (e.g. https://s3.amazonaws.com).',
    },
    access_key: {
      type: 'String',
      desc: 'S3 access key ID.',
    },
    secret_key: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      <<~DESC,
        S3 secret access key. Required when creating the endpoint; not required for ensure => absent.
        PBS never returns it, so drift is detected against the plaintext copy in
        /etc/proxmox-backup/s3.cfg, which requires the Puppet agent to run on the PBS node as root.
        Sent only when it differs from the stored value.
      DESC
      sensitive: true,
    },
    port: {
      type: 'Optional[Integer]',
      desc: 'Custom port for the S3 endpoint.',
    },
    region: {
      type: 'Optional[String]',
      desc: 'AWS/S3 region identifier.',
    },
    fingerprint: {
      type: 'Optional[String]',
      desc: 'TLS certificate fingerprint for endpoint verification.',
    },
    path_style: {
      type: 'Optional[Boolean]',
      desc: 'Use path-style S3 addressing instead of virtual-hosted-style.',
    },
    rate_in: {
      type: 'Optional[String]',
      desc: 'Inbound bandwidth rate limit as a HumanByte string (e.g. "8 MiB") or a plain byte count string.',
    },
    burst_in: {
      type: 'Optional[String]',
      desc: 'Inbound bandwidth burst allowance as a HumanByte string (e.g. "8 MiB") or a plain byte count string.',
    },
    rate_out: {
      type: 'Optional[String]',
      desc: 'Outbound bandwidth rate limit as a HumanByte string (e.g. "8 MiB") or a plain byte count string.',
    },
    burst_out: {
      type: 'Optional[String]',
      desc: 'Outbound bandwidth burst allowance as a HumanByte string (e.g. "8 MiB") or a plain byte count string.',
    },
    provider_quirks: {
      type: 'Optional[String]',
      desc: 'Provider-specific compatibility adjustments.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PBS API property names to remove during an update.',
    },
  },
)

Puppet::Type::PbsTransportAutorequire.register(:pbs_s3_endpoint)
Puppet::Type::PbsSensitiveParameters.register(:pbs_s3_endpoint)
