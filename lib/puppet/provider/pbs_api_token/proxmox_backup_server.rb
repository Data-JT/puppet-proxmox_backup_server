# frozen_string_literal: true

require_relative '../pbs_base_provider'

# @api private
module Puppet::Provider::PbsApiToken; end

# Provider for pbs_api_token resources via the PBS REST API.
#
# Tokens live under their owning user: /access/users/{userid}/token/{tokenname}.
# The namevar is the full token ID in user@realm!tokenname format.
class Puppet::Provider::PbsApiToken::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'tokenid' => :tokenid,
      'comment' => :comment,
      'enable'  => :enable,
      'expire'  => :expire,
      'delete'  => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:enable]
  end

  def get(context)
    results = []
    users = transport_get(context, '/access/users') || []
    users.each do |user|
      userid = user['userid']
      tokens = transport_get(context, "/access/users/#{userid}/token") || []
      tokens.each do |token|
        puppet_token = pbs_to_puppet(token).merge(ensure: 'present')
        # PBS omits 'enable' from the response when the token is enabled (implicit default).
        puppet_token[:enable] = true unless puppet_token.key?(:enable)
        results << puppet_token
      end
    end
    results
  end

  def create(context, name, should)
    userid, tokenname = parse_tokenid!(name)
    context.notice("Creating API token '#{name}'")
    # The token ID travels in the path, so the body is built like an update's
    # (namevar dropped) but without the 'delete' a POST does not accept.
    result = pbs_transport(context).post(
      context,
      "/access/users/#{userid}/token/#{tokenname}",
      request_body(context, should, for_update: true).except('delete'),
    )
    persist_secret(context, name, should[:secret_file], result)
  end

  def update(context, name, should)
    userid, tokenname = parse_tokenid!(name)
    context.notice("Updating API token '#{name}'")
    pbs_transport(context).put(
      context,
      "/access/users/#{userid}/token/#{tokenname}",
      request_body(context, should, for_update: true),
    )
  end

  def delete(context, name)
    userid, tokenname = parse_tokenid!(name)
    context.notice("Deleting API token '#{name}'")
    pbs_transport(context).delete(context, "/access/users/#{userid}/token/#{tokenname}")
  end

  private

  def persist_secret(context, tokenid, secret_file, result)
    secret = result['value'] if result.is_a?(Hash)
    return unless secret

    unless secret_file
      context.warning("PBS returned the one-time secret for '#{tokenid}', but secret_file is not configured; the secret was not retained")
      return
    end

    flags = File::WRONLY | File::CREAT | File::TRUNC | File::NOFOLLOW
    File.open(secret_file, flags, 0o600) do |file|
      file.chmod(0o600)
      file.write("#{secret}\n")
    end
    context.notice("Stored the one-time secret for PBS API token '#{tokenid}' in #{secret_file}")
  end

  def parse_tokenid!(tokenid)
    parts = tokenid.split('!')
    unless parts.length == 2 && parts[0].match?(%r{\A[^@\s]+@[^@\s]+\z}) && !parts[1].empty?
      raise Puppet::ResourceError,
            "tokenid must be in user@realm!tokenname format, got: #{tokenid.inspect}"
    end
    parts
  end
end
