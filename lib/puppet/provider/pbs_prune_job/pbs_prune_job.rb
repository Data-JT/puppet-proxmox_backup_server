# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_prune_job resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsPruneJob::PbsPruneJob < Puppet::Provider::PbsPruneJob::ProxmoxBackupServer
end
