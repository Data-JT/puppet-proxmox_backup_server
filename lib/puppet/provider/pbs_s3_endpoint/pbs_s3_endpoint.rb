# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_s3_endpoint resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsS3Endpoint::PbsS3Endpoint < Puppet::Provider::PbsS3Endpoint::ProxmoxBackupServer
end
