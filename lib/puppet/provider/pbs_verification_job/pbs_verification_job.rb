# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_verification_job resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsVerificationJob::PbsVerificationJob < Puppet::Provider::PbsVerificationJob::ProxmoxBackupServer
end
