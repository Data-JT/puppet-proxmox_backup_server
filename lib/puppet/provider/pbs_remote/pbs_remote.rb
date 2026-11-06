# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_remote resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsRemote::PbsRemote < Puppet::Provider::PbsRemote::ProxmoxBackupServer
end
