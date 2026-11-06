# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_user resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsUser::PbsUser < Puppet::Provider::PbsUser::ProxmoxBackupServer
end
