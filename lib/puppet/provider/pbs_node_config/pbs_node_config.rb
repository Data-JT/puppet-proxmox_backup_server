# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_node_config resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsNodeConfig::PbsNodeConfig < Puppet::Provider::PbsNodeConfig::ProxmoxBackupServer
end
