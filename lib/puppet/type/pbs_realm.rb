# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pbs_sensitive_parameters'
require_relative 'pbs_transport_autorequire'

Puppet::ResourceApi.register_type(
  name:  'pbs_realm',
  docs:  <<~DOC,
    @summary Manages a Proxmox Backup Server authentication realm (ldap, ad, or openid).

    The `type` attribute selects the realm backend and determines which of the
    remaining attributes apply:

    * `ldap`: `server1`/`server2`, `port`, `bind_dn`/`bind_password`, `mode`, `verify`,
      `capath`, `filter`, `sync_defaults_options`, `sync_attributes`, `user_classes`,
      plus the LDAP-only `base_dn` (required) and `user_attr` (required).
    * `ad`: the same LDAP/AD connection attributes as `ldap`, but `base_dn` is
      auto-detected and `user_attr` is not used.
    * `openid`: `issuer_url` (required), `client_id` (required), `client_key`,
      `username_claim`, `autocreate`, `scopes`, `prompt`, `acr_values`, `audiences`.

    @example An LDAP realm
      pbs_realm { 'corp-ldap':
        ensure        => present,
        type          => 'ldap',
        server1       => 'ldap.example.com',
        base_dn       => 'dc=example,dc=com',
        user_attr     => 'uid',
        bind_dn       => 'cn=search,dc=example,dc=com',
        bind_password => Sensitive('secret'),
        mode          => 'ldaps',
      }

    @example An OpenID Connect realm
      pbs_realm { 'sso':
        ensure         => present,
        type           => 'openid',
        issuer_url     => 'https://sso.example.com',
        client_id      => 'proxmox-backup',
        client_key     => Sensitive('oauth-secret'),
        username_claim => 'email',
        autocreate     => true,
      }
  DOC

  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this realm should exist.',
      default: 'present',
    },
    realm: {
      type:      'Pattern[/\A[A-Za-z0-9_][A-Za-z0-9._-]*\z/]',
      desc:      'The realm identifier. Must start with a letter, digit, or underscore and may contain only letters, digits, ".", "_", and "-".',
      behaviour: :namevar,
    },
    type: {
      type: "Enum['ldap', 'ad', 'openid']",
      desc: 'Realm type. Cannot be changed after creation.',
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    default: {
      type: 'Optional[Boolean]',
      desc: 'Set this realm as the default login realm.',
    },

    # ── LDAP and AD ─────────────────────────────────────────────────────────
    server1: {
      type: 'Optional[String]',
      desc: 'Primary LDAP/AD server hostname or IP. Required for ldap and ad realms.',
    },
    server2: {
      type: 'Optional[String]',
      desc: 'Fallback LDAP/AD server hostname or IP.',
    },
    port: {
      type: 'Optional[Integer]',
      desc: 'LDAP/AD server port.',
    },
    bind_dn: {
      type: 'Optional[String]',
      desc: 'DN used to bind for searches (e.g. cn=search,dc=example,dc=com).',
    },
    bind_password: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'Password for the bind DN. PBS never returns it, so drift is detected against /etc/proxmox-backup/ldap_passwords.json, which requires the agent to run on the PBS node as root.',
      sensitive: true,
    },
    mode: {
      type: "Optional[Enum['ldap', 'ldap+starttls', 'ldaps']]",
      desc: 'Connection security mode. Defaults to ldap.',
    },
    verify: {
      type: 'Optional[Boolean]',
      desc: 'Verify the server TLS certificate.',
    },
    capath: {
      type: 'Optional[String]',
      desc: 'CA certificate or directory path for TLS verification.',
    },
    filter: {
      type: 'Optional[String]',
      desc: 'LDAP filter restricting which objects are considered users.',
    },
    sync_defaults_options: {
      type: 'Optional[String]',
      desc: 'Default options for realm sync (e.g. scope=subtree).',
    },
    sync_attributes: {
      type: 'Optional[String]',
      desc: 'Attribute mapping for user sync (e.g. email=mail,firstname=givenName).',
    },
    user_classes: {
      type: 'Optional[String]',
      desc: 'Comma-separated LDAP object classes treated as user accounts.',
    },

    # ── LDAP-specific ────────────────────────────────────────────────────────
    base_dn: {
      type: 'Optional[String]',
      desc: 'Base DN for user searches. Required for ldap; auto-detected for ad.',
    },
    user_attr: {
      type: 'Optional[String]',
      desc: 'LDAP attribute that holds the username (e.g. uid, sAMAccountName). Required for ldap.',
    },

    # ── OpenID Connect ───────────────────────────────────────────────────────
    issuer_url: {
      type: 'Optional[String]',
      desc: 'OpenID provider issuer URL. Required for openid realms.',
    },
    client_id: {
      type: 'Optional[String]',
      desc: 'OAuth2 client ID registered with the provider. Required for openid realms.',
    },
    client_key: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'OAuth2 client secret. PBS stores it in cleartext in domains.cfg and returns it over the API, so it is compared directly and needs no on-node access.',
      sensitive: true,
    },
    username_claim: {
      type: 'Optional[String]',
      desc: 'JWT claim used as the PBS username (e.g. email, sub).',
    },
    autocreate: {
      type: 'Optional[Boolean]',
      desc: 'Automatically create PBS users on first successful OpenID login.',
    },
    scopes: {
      type: 'Optional[String]',
      desc: 'Space-separated list of OAuth2 scopes to request.',
    },
    prompt: {
      type: 'Optional[String]',
      desc: 'OpenID prompt parameter (e.g. login, consent).',
    },
    acr_values: {
      type: 'Optional[String]',
      desc: 'Space-separated Authentication Context Class References.',
    },
    audiences: {
      type: 'Optional[String]',
      desc: 'Space-separated list of accepted token audiences.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PBS API property names to remove during an update.',
    },
  },
)

Puppet::Type::PbsTransportAutorequire.register(:pbs_realm)
Puppet::Type::PbsSensitiveParameters.register(:pbs_realm)
