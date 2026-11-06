# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsDatastore; end

# Provider for pbs_datastore resources via the PBS REST API.
class Puppet::Provider::PbsDatastore::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'name'         => :name,
      'path'         => :path,
      'comment'      => :comment,
      'gc-schedule'  => :gc_schedule,
      'delete'       => :delete_properties,
    }
  end

  def get(context)
    @path_by_name = {}
    (transport_get(context, '/config/datastore') || []).map do |ds|
      @path_by_name[ds['name']] = ds['path']
      pbs_to_puppet(ds).merge(ensure: 'present')
    end
  end

  def create(context, name, should)
    context.notice("Creating datastore '#{name}'")
    transport = pbs_transport(context)
    upid = transport.post(context, '/config/datastore', request_body(context, should))
    transport.wait_for_task(context, upid)
  end

  def update(context, name, should)
    validate_path_unchanged(name, should[:path])
    context.notice("Updating datastore '#{name}'")
    body = should.reject { |key, _| key == :path } # path is create-only and rejected by the PBS PUT endpoint
    pbs_transport(context).put(context, "/config/datastore/#{name}", request_body(context, body, for_update: true))
  end

  def delete(context, name)
    context.notice("Deleting datastore '#{name}'")
    transport = pbs_transport(context)
    upid = transport.delete(context, "/config/datastore/#{name}")
    transport.wait_for_task(context, upid)
  end

  private

  # path cannot be changed via the PBS API (the PUT endpoint rejects it), so
  # silently dropping a differing path would report a corrective change on
  # every run without ever converging. Fail loudly instead.
  def validate_path_unchanged(name, wanted_path)
    current_path = @path_by_name&.fetch(name, nil)
    return unless wanted_path && current_path && current_path != wanted_path

    raise Puppet::ResourceError,
          "pbs_datastore '#{name}': path is create-only; cannot change '#{current_path}' to '#{wanted_path}'. " \
          'Delete and recreate the datastore to move it.'
  end
end
