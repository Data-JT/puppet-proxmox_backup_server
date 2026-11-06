# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsPruneJob; end

# Provider for pbs_prune_job resources via the PBS REST API.
class Puppet::Provider::PbsPruneJob::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'id'           => :id,
      'store'        => :store,
      'schedule'     => :job_schedule,
      'ns'           => :ns,
      'keep-last'    => :keep_last,
      'keep-hourly'  => :keep_hourly,
      'keep-daily'   => :keep_daily,
      'keep-weekly'  => :keep_weekly,
      'keep-monthly' => :keep_monthly,
      'keep-yearly'  => :keep_yearly,
      'comment'      => :comment,
      'delete'       => :delete_properties,
    }
  end

  def get(context)
    (transport_get(context, '/config/prune') || []).map do |job|
      pbs_to_puppet(job).merge(ensure: 'present')
    end
  end

  def create(context, name, should)
    context.notice("Creating prune job '#{name}'")
    pbs_transport(context).post(context, '/config/prune', request_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating prune job '#{name}'")
    pbs_transport(context).put(context, "/config/prune/#{name}", request_body(context, should, for_update: true))
  end

  def delete(context, name)
    context.notice("Deleting prune job '#{name}'")
    pbs_transport(context).delete(context, "/config/prune/#{name}")
  end
end
