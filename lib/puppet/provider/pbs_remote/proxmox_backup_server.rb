# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsRemote; end

# Provider for pbs_remote resources via the PBS REST API.
#
# The API withholds the password on GET, but PBS writes it to
# /etc/proxmox-backup/remote.cfg base64-encoded (verified on 4.2.1), so drift
# is detected by decoding that. base64 is encoding, not encryption: the file is
# 0640 root:backup, so any member of the backup group can read the credential.
class Puppet::Provider::PbsRemote::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'name'           => :name,
      'host'           => :host,
      'port'           => :port,
      'auth-id'        => :userid,
      'password'       => :password,
      'fingerprint'    => :fingerprint,
      'use-node-proxy' => :use_node_proxy,
      'comment'        => :comment,
      'delete'         => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:use_node_proxy]
  end

  def self.secret_attributes
    [:password]
  end

  def stored_secret(_attribute_name, current)
    SecretStore.remote_password(current[:name])
  end

  def get(context)
    (transport_get(context, '/config/remote') || []).map do |remote|
      puppet_hash = pbs_to_puppet(remote).merge(ensure: 'present')
      puppet_hash.merge(secret_placeholders(puppet_hash))
    end
  end

  def create(context, name, should)
    context.notice("Creating remote '#{name}'")
    pbs_transport(context).post(context, '/config/remote', request_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating remote '#{name}'")
    # The password is sent only when it actually differs from the copy in
    # remote.cfg. PBS keeps a secret that a PUT omits, so an unchanged
    # credential is never rewritten and never mints a change event.
    pbs_transport(context).put(context, "/config/remote/#{name}", update_body(context, should))
  end

  def delete(context, name)
    context.notice("Deleting remote '#{name}'")
    pbs_transport(context).delete(context, "/config/remote/#{name}")
  end
end
