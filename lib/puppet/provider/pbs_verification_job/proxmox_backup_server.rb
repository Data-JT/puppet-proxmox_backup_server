# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsVerificationJob; end

# Provider for pbs_verification_job resources via the PBS REST API.
class Puppet::Provider::PbsVerificationJob::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'id'              => :id,
      'store'           => :store,
      'schedule'        => :job_schedule,
      'outdated-after'  => :outdated_after,
      'ignore-verified' => :ignore_verified,
      'comment'         => :comment,
      'delete'          => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:ignore_verified]
  end

  def get(context)
    (transport_get(context, '/config/verify') || []).map do |job|
      pbs_to_puppet(job).merge(ensure: 'present')
    end
  end

  def create(context, name, should)
    context.notice("Creating verification job '#{name}'")
    pbs_transport(context).post(context, '/config/verify', request_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating verification job '#{name}'")
    pbs_transport(context).put(context, "/config/verify/#{name}", request_body(context, should, for_update: true))
  end

  def delete(context, name)
    context.notice("Deleting verification job '#{name}'")
    pbs_transport(context).delete(context, "/config/verify/#{name}")
  end
end
