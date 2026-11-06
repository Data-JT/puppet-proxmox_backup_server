# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsS3Endpoint; end

# Provider for pbs_s3_endpoint resources via the PBS REST API.
#
# Maps to /config/s3 — manages S3 client credentials and connection settings.
# The GET endpoint never returns secret-key, but PBS writes it in plaintext to
# /etc/proxmox-backup/s3.cfg (verified on 4.2.1), so drift is detected against
# that file. Note that s3.cfg is 0640 root:backup, so the secret key is
# readable by any member of the backup group.
class Puppet::Provider::PbsS3Endpoint::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'id'               => :id,
      'endpoint'         => :endpoint,
      'access-key'       => :access_key,
      'secret-key'       => :secret_key,
      'port'             => :port,
      'region'           => :region,
      'fingerprint'      => :fingerprint,
      'path-style'       => :path_style,
      'rate-in'          => :rate_in,
      'burst-in'         => :burst_in,
      'rate-out'         => :rate_out,
      'burst-out'        => :burst_out,
      'provider-quirks'  => :provider_quirks,
      'delete'           => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:path_style]
  end

  def self.secret_attributes
    [:secret_key]
  end

  def stored_secret(_attribute_name, current)
    SecretStore.s3_secret_key(current[:id])
  end

  def get(context)
    (transport_get(context, '/config/s3') || []).map do |ep|
      puppet_hash = pbs_to_puppet(ep).merge(ensure: 'present')
      puppet_hash.merge(secret_placeholders(puppet_hash))
    end
  end

  def create(context, name, should)
    if should[:secret_key].nil?
      raise Puppet::ResourceError,
            "pbs_s3_endpoint '#{name}': secret_key is required when creating an S3 endpoint"
    end

    context.notice("Creating S3 endpoint '#{name}'")
    pbs_transport(context).post(context, '/config/s3', request_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating S3 endpoint '#{name}'")
    # secret_key is sent only when it differs from the copy in s3.cfg. PBS
    # keeps a secret that a PUT omits, so an unchanged key is never rewritten.
    pbs_transport(context).put(context, "/config/s3/#{name}", update_body(context, should))
  end

  def delete(context, name)
    context.notice("Deleting S3 endpoint '#{name}'")
    pbs_transport(context).delete(context, "/config/s3/#{name}")
  end
end
