# frozen_string_literal: true

require 'socket'
require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsNodeConfig; end

# Provider for pbs_node_config resources via the PBS REST API.
#
# Maps to GET/PUT /nodes/{node}/config. Since there is exactly one node config
# (the local node's), get() always returns a single resource whose title is the
# local short hostname; declaring any other title raises an error. delete()
# raises as well because the node config object cannot be removed — remove the
# resource from the manifest to stop managing it.
class Puppet::Provider::PbsNodeConfig::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'description'       => :description,
      'email-from'        => :email_from,
      'http-proxy'        => :http_proxy,
      'default-lang'      => :default_lang,
      'task-log-max-days' => :task_log_max_days,
      'consent-text'      => :consent_text,
      'location'          => :location,
      'delete'            => :delete_properties,
    }
  end

  def self.boolean_attributes
    []
  end

  def get(context)
    node_name = local_node_name
    config = transport_get(context, "/nodes/#{node_name}/config")
    return [] if missing_transport_result?(config)

    config ||= {}
    result = pbs_to_puppet(config).merge(ensure: 'present', node: node_name)
    result[:description] = result[:description].chomp if result[:description].is_a?(String)
    [result]
  end

  # PBS strips a single trailing newline from the stored description, so a
  # manifest value ending in "\n" would otherwise drift forever.
  def canonicalize(_context, resources)
    resources.map do |resource|
      munged = resource.dup
      munged[:description] = munged[:description].chomp if munged[:description].is_a?(String)
      munged
    end
  end

  def create(context, name, should)
    # Node config always exists; create is identical to update.
    validate_local_node!(name)
    update(context, name, should)
  end

  def update(context, name, should)
    validate_local_node!(name)
    context.notice("Updating node config for '#{name}'")
    pbs_transport(context).put(context, "/nodes/#{name}/config", request_body(context, should, for_update: true))
  end

  def delete(_context, name)
    validate_local_node!(name)
    raise Puppet::ResourceError,
          "pbs_node_config '#{name}': the node configuration cannot be deleted; " \
          'remove the resource from the manifest to stop managing it'
  end

  private

  def local_node_name
    Socket.gethostname.split('.').first
  end

  def validate_local_node!(name)
    local = local_node_name
    return if name == local

    raise Puppet::ResourceError,
          "pbs_node_config title must be the local node name '#{local}', got '#{name}'"
  end
end
