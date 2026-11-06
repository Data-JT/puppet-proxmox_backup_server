# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsNotificationTarget; end

# Provider for pbs_notification_target resources via the PBS REST API.
#
# All three secrets live in /etc/proxmox-backup/notifications-priv.cfg, a
# separate 0600 root:root file from the public notifications.cfg (verified on
# 4.2.1): smtp -> password, gotify -> token, webhook -> secret.
class Puppet::Provider::PbsNotificationTarget::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  TARGET_TYPES = ['sendmail', 'smtp', 'gotify', 'webhook'].freeze unless const_defined?(:TARGET_TYPES)

  # The priv-file field backing each secret attribute.
  SECRET_FIELDS = { smtp_password: 'password', token: 'token', secret: 'secret' }.freeze

  def self.attribute_map
    {
      'name'          => :name,
      'comment'       => :comment,
      'disable'       => :disable,
      'author'        => :author,
      'from-address'  => :from_address,
      'mailto'        => :mailto,
      'mailto-user'   => :mailto_user,
      'server'        => :server,
      'port'          => :port,
      'mode'          => :mode,
      'username'      => :username,
      'password'      => :smtp_password,
      'token'         => :token,
      'url'           => :url,
      'method'        => :http_method,
      'body'          => :body,
      'header'        => :header,
      'secret'        => :secret,
      'delete'        => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:disable]
  end

  def self.secret_attributes
    SECRET_FIELDS.keys
  end

  def stored_secret(attribute_name, current)
    values = SecretStore.notification_secrets(current[:type], current[:name], SECRET_FIELDS[attribute_name])
    return nil if values.empty?

    values
  end

  # The webhook secret is an unordered set of name/value pairs rendered as PBS
  # property strings; everything else is a single scalar.
  def secret_matches?(attribute_name, stored, desired)
    return webhook_secrets_match?(stored, desired) if attribute_name == :secret

    stored.first == desired
  end

  def get(context)
    @type_by_name = {}
    results = []
    TARGET_TYPES.each do |target_type|
      items = transport_get(context, "/config/notifications/endpoints/#{target_type}") || []
      items.each do |item|
        puppet_hash = pbs_to_puppet(item).merge(ensure: 'present', type: target_type)
        @type_by_name[item['name']] = target_type
        results << puppet_hash.merge(secret_placeholders(puppet_hash))
      end
    end
    results
  end

  def create(context, name, should)
    target_type = should[:type]
    context.notice("Creating #{target_type} notification target '#{name}'")
    pbs_transport(context).post(context, "/config/notifications/endpoints/#{target_type}", request_body(context, should))
  end

  def update(context, name, should)
    target_type = should[:type]
    validate_type_unchanged(name, target_type)
    context.notice("Updating #{target_type} notification target '#{name}'")
    pbs_transport(context).put(context, "/config/notifications/endpoints/#{target_type}/#{name}", update_body(context, should))
  end

  # `secret` is declared Array[Hash], so its placeholder must be one too. The
  # stored names are reported and the values withheld -- which is exactly what
  # the PBS API itself returns for a webhook secret.
  def secret_placeholder(attribute_name, stored)
    return super unless attribute_name == :secret

    stored.map { |entry| { 'name' => property_string(entry)['name'] } }
  end

  def delete(context, name)
    target_type = @type_by_name&.fetch(name, nil)
    unless target_type
      raise Puppet::ResourceError,
            "cannot delete notification target '#{name}': target type unknown - resource not found on the server?"
    end
    context.notice("Deleting notification target '#{name}'")
    pbs_transport(context).delete(context, "/config/notifications/endpoints/#{target_type}/#{name}")
  end

  private

  # Compares the webhook secret set: name -> base64 value, order-insensitive,
  # because PBS renders the entries in its own order.
  #
  # An entry declared without a value means "keep the stored secret", which is
  # how PBS itself expresses an unchanged webhook secret, so such an entry
  # matches on name alone.
  def webhook_secrets_match?(stored, desired)
    stored_map = stored.to_h { |entry| secret_pair(property_string(entry)) }
    values_match?(stored_map, Array(desired).to_h { |entry| secret_pair(entry) })
  end

  def values_match?(stored_map, desired_map)
    stored_map.keys.sort == desired_map.keys.sort &&
      desired_map.all? { |name, value| value.to_s.empty? || value == stored_map[name] }
  end

  def secret_pair(entry)
    [entry['name'].to_s, entry['value']]
  end

  # PBS property string: "name=<name>,value=<base64>". The value is split off
  # at the first '=' only, so base64 padding survives intact.
  def property_string(entry)
    entry.to_s.split(',').each_with_object({}) do |pair, result|
      key, value = pair.split('=', 2)
      result[key] = value
    end
  end

  def validate_type_unchanged(name, target_type)
    current_type = @type_by_name&.fetch(name, nil)
    return unless current_type && current_type != target_type

    raise Puppet::ResourceError,
          "notification target '#{name}' type cannot be changed from #{current_type} to #{target_type}; recreate the resource instead"
  end
end
