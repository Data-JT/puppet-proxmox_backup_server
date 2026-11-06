# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsAcl; end

# Provider for pbs_acl resources via the PBS REST API.
class Puppet::Provider::PbsAcl::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'path'      => :acl_path,
      'ugid'      => :ugid,
      'roleid'    => :role, # PBS >= 2.x returns 'roleid'; 'role' below is a fallback for older API responses
      'role'      => :role,
      'propagate' => :propagate,
    }
  end

  def self.boolean_attributes
    [:propagate]
  end

  def get(context)
    (transport_get(context, '/access/acl') || []).map do |entry|
      attrs = pbs_to_puppet(entry).merge(ensure: 'present')
      attrs.merge(title: "#{attrs[:acl_path]}|#{attrs[:ugid]}|#{attrs[:role]}")
    end
  end

  def create(context, name, should)
    context.notice("Creating ACL '#{name}'")
    pbs_transport(context).put(context, '/access/acl', acl_body(should))
  end

  def update(context, name, should)
    context.notice("Updating ACL '#{name}'")
    pbs_transport(context).put(context, '/access/acl', acl_body(should))
  end

  # name is a namevar hash (e.g. { acl_path: '/', ugid: 'user@pbs', role: 'Admin' }), not a
  # plain string. Resource API passes a hash for resources with multiple namevars.
  def delete(context, name)
    context.notice("Deleting ACL '#{name}'")
    pbs_transport(context).put(context, '/access/acl', acl_body(name).merge('delete' => true))
  end

  private

  # Builds the PUT /access/acl request body from a `should` hash (create/update)
  # or a namevar hash (delete). The propagate key is omitted when absent so that
  # delete requests only carry the identifying fields plus delete: true.
  def acl_body(attrs)
    body = {
      'path'    => attrs[:acl_path],
      'auth-id' => attrs[:ugid],
      'role'    => attrs[:role],
    }
    body['propagate'] = to_bool(attrs[:propagate]) if attrs.key?(:propagate)
    body
  end
end
