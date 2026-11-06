# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsSyncJob; end

# Provider for pbs_sync_job resources via the PBS REST API.
class Puppet::Provider::PbsSyncJob::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'id'              => :id,
      'store'           => :store,
      'remote'          => :remote,
      'remote-store'    => :remote_store,
      'remote-ns'       => :remote_ns,
      'ns'              => :ns,
      'max-depth'       => :max_depth,
      'sync-direction'  => :sync_direction,
      'owner'           => :owner,
      'group-filter'    => :group_filter,
      'schedule'        => :job_schedule,
      'remove-vanished' => :remove_vanished,
      'transfer-last'   => :transfer_last,
      'resync-corrupt'  => :resync_corrupt,
      'encrypted-only'  => :encrypted_only,
      'verified-only'   => :verified_only,
      'rate-in'         => :rate_in,
      'worker-threads'  => :worker_threads,
      'comment'         => :comment,
      'delete'          => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:remove_vanished, :resync_corrupt, :encrypted_only, :verified_only]
  end

  def get(context)
    (transport_get(context, '/config/sync') || []).map do |job|
      pbs_to_puppet(job).merge(ensure: 'present')
    end
  end

  def create(context, name, should)
    context.notice("Creating sync job '#{name}'")
    pbs_transport(context).post(context, '/config/sync', request_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating sync job '#{name}'")
    pbs_transport(context).put(context, "/config/sync/#{name}", request_body(context, should, for_update: true))
  end

  def delete(context, name)
    context.notice("Deleting sync job '#{name}'")
    pbs_transport(context).delete(context, "/config/sync/#{name}")
  end
end
