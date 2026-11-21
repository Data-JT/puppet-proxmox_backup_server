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
    (transport_get(context, '/config/datastore') || []).map do |ds|
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
    context.notice("Updating datastore '#{name}'")
    body = without_create_only(context, should)
    pbs_transport(context).put(context, "/config/datastore/#{name}", request_body(context, body, for_update: true))
  end

  def delete(context, name)
    context.notice("Deleting datastore '#{name}'")
    transport = pbs_transport(context)
    upid = transport.delete(context, "/config/datastore/#{name}")
    transport.wait_for_task(context, upid)
  end
end
