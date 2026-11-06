# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsRealm; end

# Provider for pbs_realm resources via the PBS REST API.
#
# Each realm type has its own endpoint under /config/access/{type}.
# The type attribute routes all operations to the correct sub-path.
#
# The two secrets are handled differently, because PBS treats them
# differently (verified on 4.2.1):
#
#   bind_password  ldap/ad  withheld by the API, stored plaintext in
#                           /etc/proxmox-backup/ldap_passwords.json
#   client_key     openid   returned verbatim by GET, so it is an ordinary
#                           property needing no store at all
class Puppet::Provider::PbsRealm::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  REALM_TYPES = ['ldap', 'ad', 'openid'].freeze unless const_defined?(:REALM_TYPES)

  def self.attribute_map
    {
      'realm'                 => :realm,
      'comment'               => :comment,
      'default'               => :default,
      # LDAP / AD
      'server1'               => :server1,
      'server2'               => :server2,
      'port'                  => :port,
      'bind-dn'               => :bind_dn,
      'password'              => :bind_password,
      'mode'                  => :mode,
      'verify'                => :verify,
      'capath'                => :capath,
      'filter'                => :filter,
      'sync-defaults-options' => :sync_defaults_options,
      'sync-attributes'       => :sync_attributes,
      'user-classes'          => :user_classes,
      # LDAP-only
      'base-dn'               => :base_dn,
      'user-attr'             => :user_attr,
      # OpenID
      'issuer-url'            => :issuer_url,
      'client-id'             => :client_id,
      'client-key'            => :client_key,
      'username-claim'        => :username_claim,
      'autocreate'            => :autocreate,
      'scopes'                => :scopes,
      'prompt'                => :prompt,
      'acr-values'            => :acr_values,
      'audiences'             => :audiences,
      'delete'                => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:default, :verify, :autocreate]
  end

  def self.secret_attributes
    [:bind_password]
  end

  # ldap and ad realms share ldap_passwords.json, keyed by realm name. openid
  # realms are absent from it, which is correct: client_key round-trips
  # through the API and is compared as a normal property.
  def stored_secret(_attribute_name, current)
    SecretStore.realm_password(current[:realm])
  end

  def get(context)
    @type_by_realm = {}
    results = []
    REALM_TYPES.each do |realm_type|
      items = transport_get(context, "/config/access/#{realm_type}") || []
      items.each do |item|
        puppet_hash = pbs_to_puppet(item).merge(ensure: 'present', type: realm_type)
        @type_by_realm[item['realm']] = realm_type
        results << puppet_hash.merge(secret_placeholders(puppet_hash))
      end
    end
    results
  end

  def create(context, name, should)
    realm_type = should[:type]
    context.notice("Creating #{realm_type} realm '#{name}'")
    pbs_transport(context).post(context, "/config/access/#{realm_type}", request_body(context, should))
  end

  def update(context, name, should)
    realm_type = should[:type]
    validate_type_unchanged(name, realm_type)
    context.notice("Updating #{realm_type} realm '#{name}'")
    pbs_transport(context).put(context, "/config/access/#{realm_type}/#{name}", update_body(context, should))
  end

  def delete(context, name)
    realm_type = @type_by_realm&.fetch(name, nil)
    unless realm_type
      raise Puppet::ResourceError,
            "cannot delete realm '#{name}': realm type unknown - resource not found on the server?"
    end
    context.notice("Deleting realm '#{name}'")
    pbs_transport(context).delete(context, "/config/access/#{realm_type}/#{name}")
  end

  private

  def validate_type_unchanged(name, realm_type)
    current_type = @type_by_realm&.fetch(name, nil)
    return unless current_type && current_type != realm_type

    raise Puppet::ResourceError,
          "realm '#{name}' type cannot be changed from #{current_type} to #{realm_type}; recreate the resource instead"
  end
end
