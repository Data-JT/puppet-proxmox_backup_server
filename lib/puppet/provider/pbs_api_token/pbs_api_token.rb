# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_api_token resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsApiToken::PbsApiToken < Puppet::Provider::PbsApiToken::ProxmoxBackupServer
end
