# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_sync_job resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsSyncJob::PbsSyncJob < Puppet::Provider::PbsSyncJob::ProxmoxBackupServer
end
