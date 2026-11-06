# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_datastore resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsDatastore::PbsDatastore < Puppet::Provider::PbsDatastore::ProxmoxBackupServer
end
