# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_sensitive_parameters'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:  'pbs_notification_target',
  docs:  <<~DOC,
    @summary Manages a Proxmox Backup Server notification target (sendmail, smtp, gotify, or webhook).

    The `type` attribute selects the delivery mechanism and determines which of
    the remaining attributes apply: sendmail/smtp targets use the mail-related
    attributes, gotify targets use `server` and `token`, and webhook targets use
    `url`, `http_method`, `body`, `header`, and `secret`.

    @example An SMTP relay target
      pbs_notification_target { 'smtp-relay':
        ensure        => present,
        type          => 'smtp',
        server        => 'smtp.example.com',
        mode          => 'starttls',
        username      => 'pbs',
        smtp_password => Sensitive('secret'),
        from_address  => 'pbs@example.com',
        mailto        => ['ops@example.com'],
      }

    @example A webhook target
      pbs_notification_target { 'webhook-alerts':
        ensure      => present,
        type        => 'webhook',
        url         => 'https://hooks.example.com/notify',
        http_method => 'post',
        body        => '{"text": "{{ message }}"}',
        # header/secret values must be base64-encoded (PBS KeyAndBase64Val schema):
        header      => [{ 'name' => 'Content-Type', 'value' => 'YXBwbGljYXRpb24vanNvbg==' }],
        secret      => [{ 'name' => 'token', 'value' => 'aHVudGVyMg==' }],
      }
  DOC

  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this notification target should exist.',
      default: 'present',
    },
    name: {
      type:      'Pattern[/\A[A-Za-z0-9_][A-Za-z0-9._-]*\z/]',
      desc:      'The notification target name. Must start with a letter, digit, or underscore and may contain only letters, digits, ".", "_", and "-".',
      behaviour: :namevar,
    },
    type: {
      type: 'Enum[sendmail, smtp, gotify, webhook]',
      desc: 'Target type. Determines the delivery mechanism. Cannot be changed after creation.',
    },
    disable: {
      type: 'Optional[Boolean]',
      desc: 'Disable this notification target.',
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    # Sendmail and SMTP
    author: {
      type: 'Optional[String]',
      desc: 'Author name shown in sent emails. Defaults to "Proxmox Backup Server (<hostname>)".',
    },
    from_address: {
      type: 'Optional[String]',
      desc: 'From address for sent emails. Required for smtp targets.',
    },
    mailto: {
      type: 'Optional[Array[String]]',
      desc: 'List of email addresses to notify.',
    },
    mailto_user: {
      type: 'Optional[Array[String]]',
      desc: 'List of PBS user IDs whose configured email addresses receive notifications.',
    },
    # SMTP and Gotify share the server field
    server: {
      type: 'Optional[String]',
      desc: 'SMTP relay hostname/IP (smtp) or Gotify server URL (gotify).',
    },
    # SMTP-specific
    port: {
      type: 'Optional[Integer]',
      desc: 'SMTP port. Defaults to 25 (insecure), 465 (tls), or 587 (starttls).',
    },
    mode: {
      type: 'Optional[Enum[insecure, starttls, tls]]',
      desc: 'SMTP TLS mode. Defaults to tls.',
    },
    username: {
      type: 'Optional[String]',
      desc: 'SMTP authentication username.',
    },
    smtp_password: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      <<~DESC,
        SMTP authentication password. PBS never returns it, so drift is detected against the copy in
        /etc/proxmox-backup/notifications-priv.cfg, which requires the Puppet agent to run on the PBS
        node as root. Sent only when it differs from the stored value.
      DESC
      sensitive: true,
    },
    # Gotify-specific
    token: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'Gotify authentication token. PBS never returns it, so drift is detected against /etc/proxmox-backup/notifications-priv.cfg, which requires the agent to run on the PBS node as root.',
      sensitive: true,
    },
    # Webhook-specific
    url: {
      type: 'Optional[String]',
      desc: 'Webhook URL. Required for webhook targets.',
    },
    http_method: {
      type: 'Optional[Enum[post, put, get]]',
      desc: 'HTTP method for webhook requests. Defaults to post.',
    },
    body: {
      type: 'Optional[String]',
      desc: 'Webhook request body template (supports handlebars).',
    },
    header: {
      type: 'Optional[Array[Hash]]',
      desc: <<~DESC,
        Webhook HTTP headers. Each entry is a hash with "name" and "value" keys, where
        the value MUST be base64-encoded (PBS KeyAndBase64Val schema), e.g.
        {'name' => 'X-Token', 'value' => 'c2VjcmV0'} for the plaintext 'secret'.
        Plaintext values are rejected by the PBS API or cause perpetual drift.
      DESC
    },
    secret: {
      type:      'Optional[Variant[Array[Hash], Sensitive[Array[Hash]]]]',
      desc:      <<~DESC,
        Webhook secrets available in templates. Each entry has a "name" and an optional "value", which
        MUST be base64-encoded (PBS KeyAndBase64Val schema), e.g.
        {'name' => 'token', 'value' => 'aHVudGVyMg=='} for the plaintext 'hunter2'. An entry given
        without a value keeps whatever PBS already stores. The API returns secret names but never
        their values, so drift is detected against /etc/proxmox-backup/notifications-priv.cfg, which
        requires the Puppet agent to run on the PBS node as root.
      DESC
      sensitive: true,
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PBS API property names to remove during an update.',
    },
  },
)

Puppet::Type::PbsTransportAutorequire.register(:pbs_notification_target)
Puppet::Type::PbsSensitiveParameters.register(:pbs_notification_target)
