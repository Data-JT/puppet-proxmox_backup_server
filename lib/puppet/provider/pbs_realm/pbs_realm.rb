# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_realm resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsRealm::PbsRealm < Puppet::Provider::PbsRealm::ProxmoxBackupServer
end
