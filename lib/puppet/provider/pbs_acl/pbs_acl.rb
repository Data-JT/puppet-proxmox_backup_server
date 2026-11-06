# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_acl resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsAcl::PbsAcl < Puppet::Provider::PbsAcl::ProxmoxBackupServer
end
