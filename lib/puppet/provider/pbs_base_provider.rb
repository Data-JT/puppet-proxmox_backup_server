# frozen_string_literal: true

require 'puppet/resource_api/simple_provider'
require 'yaml'
require_relative '../../puppet_x/proxmox_backup_server/secret_comparison'

# Base provider with shared PBS attribute mapping helpers.
class Puppet::Provider::PbsBaseProvider < Puppet::ResourceApi::SimpleProvider
  # Drift detection for the secrets PBS never returns. Kept in its own module
  # so this class stays about mapping Puppet attributes to the PBS API.
  include PuppetX::ProxmoxBackupServer::SecretComparison

  # Raised when the Puppet-managed transport config file is absent or not a
  # usable YAML mapping. Subclasses Puppet::ResourceError so it still surfaces
  # as a regular resource failure wherever it is not rescued explicitly.
  class TransportConfigMissing < Puppet::ResourceError; end

  MISSING_TRANSPORT_RESULT = [].freeze

  def self.attribute_map
    {}
  end

  def self.boolean_attributes
    []
  end

  # Attributes whose value PBS never returns, mapped to nothing here; each
  # provider that owns secrets overrides this and implements stored_secret.
  def self.secret_attributes
    []
  end

  def self.config_path
    File.join(Puppet.settings[:confdir], 'pbs_transport.yaml')
  end

  def self.build_transport(context)
    require 'puppet/transport/proxmox_backup_server'
    Puppet::Transport::ProxmoxBackupServer.new(context, read_transport_config)
  end

  def self.read_transport_config
    config = YAML.safe_load_file(config_path)
    unless config.is_a?(Hash)
      raise TransportConfigMissing,
            "PBS transport config at #{config_path} is empty or not a YAML mapping; " \
            'ensure the proxmox_backup_server class is applied before managing PBS resources'
    end
    config.transform_keys(&:to_sym)
  rescue Errno::ENOENT, Errno::ENOTDIR
    raise TransportConfigMissing,
          "PBS transport config not found at #{config_path}; " \
          'ensure the proxmox_backup_server class is applied before managing PBS resources'
  end

  def pbs_transport(context)
    signature = transport_config_signature
    if @pbs_transport.nil? || signature != @transport_config_signature
      @pbs_transport = self.class.build_transport(context)
      @transport_config_signature = signature
    end
    @pbs_transport
  end

  # State discovery happens before catalog resources are applied. Treat a
  # missing managed transport file as an empty result; set() refreshes state
  # after the transport class has been applied.
  def transport_get(context, path, query = nil)
    pbs_transport(context).get(context, path, query)
  rescue TransportConfigMissing
    @transport_config_missing = true
    MISSING_TRANSPORT_RESULT
  end

  def set(context, changes)
    changes = refresh_changes(context, changes) if @transport_config_missing
    super
  end

  # Secrets are handled by SecretComparison#insync?, reached through super.
  def insync?(context, title, attribute_name, is, should)
    return delete_properties_insync?(is, should) if attribute_name == :delete_properties

    super
  end

  def pbs_to_puppet(hash)
    result = {}
    self.class.attribute_map.each do |pbs_key, puppet_key|
      next unless hash.key?(pbs_key.to_s)
      value = hash[pbs_key.to_s]
      value = to_bool(value) if self.class.boolean_attributes.include?(puppet_key)
      result[puppet_key] = value
    end
    result
  end

  def puppet_to_pbs(hash)
    result = {}
    self.class.attribute_map.each do |pbs_key, puppet_key|
      next unless hash.key?(puppet_key)
      value = hash[puppet_key]
      next if value.nil?
      value = value.unwrap if value.respond_to?(:unwrap)
      value = to_bool(value) if self.class.boolean_attributes.include?(puppet_key)
      result[pbs_key.to_s] = value
    end
    result
  end

  # Create requests never carry 'delete': a resource being created has no
  # properties to delete, and the API rejects the parameter on POST.
  def request_body(context, should, for_update: false)
    body = should.dup
    body.delete(:ensure)
    context.type.namevars.each { |nv| body.delete(nv) } if for_update
    result = puppet_to_pbs(body)
    for_update ? normalize_delete_properties(result) : result.except('delete')
  end

  # Clearing optional properties: `delete_properties` names API properties to
  # remove on update. A provider opts in by mapping 'delete' => :delete_properties
  # in attribute_map, which passes the list to the endpoint's `delete` parameter.
  #
  # Whether that parameter is sent as a JSON list rather than a comma-separated
  # string. PVE's Perl API takes the string on most endpoints; the Rust APIs of
  # PBS and PDM take the list.
  def self.delete_properties_as_array?
    true
  end

  # GET never reports delete_properties, so it is in sync once none of the
  # named properties is present any more: the delete is sent only while one
  # still is. A name outside attribute_map could never be observed as gone and
  # would re-send the delete on every run, so it is rejected instead.
  def delete_properties_insync?(current, desired)
    requested = Array(desired[:delete_properties])
    reject_unobservable_deletions(requested)
    attribute_map = self.class.attribute_map
    requested.none? { |api_key| current.key?(attribute_map[api_key]) }
  end

  private

  def transport_config_signature
    stat = File.stat(self.class.config_path)
    [stat.mtime.to_f, stat.size]
  rescue Errno::ENOENT, Errno::ENOTDIR
    nil
  end

  def missing_transport_result?(value)
    value.equal?(MISSING_TRANSPORT_RESULT)
  end

  def refresh_changes(context, changes)
    @pbs_transport = nil
    @transport_config_signature = nil
    @transport_config_missing = false
    current = get(context) || []

    changes.transform_values do |change|
      should = change[:should]
      actual = current.find do |resource|
        context.type.namevars.all? { |namevar| resource[namevar] == should[namevar] }
      end
      change.merge(is: actual || absent_state(context, should))
    end
  end

  def absent_state(context, should)
    context.type.namevars.to_h { |namevar| [namevar, should[namevar]] }.merge(ensure: 'absent')
  end

  def normalize_delete_properties(body)
    return body unless body.key?('delete')

    values = Array(body['delete'])
    body['delete'] = self.class.delete_properties_as_array? ? values : values.join(',')
    body
  end

  def reject_unobservable_deletions(requested)
    unknown = requested.reject { |api_key| self.class.attribute_map.key?(api_key) }
    return if unknown.empty?

    raise Puppet::ResourceError, "Cannot observe deleted PBS properties: #{unknown.join(', ')}"
  end

  def to_bool(value)
    return true if [true, 1, '1', 'true', :true].include?(value)
    return false if [false, 0, '0', 'false', :false].include?(value)

    value
  end
end
