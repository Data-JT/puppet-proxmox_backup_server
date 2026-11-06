# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsNotificationMatcher; end

# Provider for pbs_notification_matcher resources via the PBS REST API.
class Puppet::Provider::PbsNotificationMatcher::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'name'           => :name,
      'target'         => :target,
      'match-severity' => :match_severity,
      'match-calendar' => :match_calendar,
      'match-field'    => :match_field,
      'mode'           => :mode,
      'invert-match'   => :invert_match,
      'disable'        => :disable,
      'comment'        => :comment,
      'delete'         => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:invert_match, :disable]
  end

  def get(context)
    (transport_get(context, '/config/notifications/matchers') || []).map do |matcher|
      pbs_to_puppet(matcher).merge(ensure: 'present')
    end
  end

  def create(context, name, should)
    context.notice("Creating notification matcher '#{name}'")
    pbs_transport(context).post(context, '/config/notifications/matchers', request_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating notification matcher '#{name}'")
    pbs_transport(context).put(context, "/config/notifications/matchers/#{name}", request_body(context, should, for_update: true))
  end

  def delete(context, name)
    context.notice("Deleting notification matcher '#{name}'")
    pbs_transport(context).delete(context, "/config/notifications/matchers/#{name}")
  end
end
