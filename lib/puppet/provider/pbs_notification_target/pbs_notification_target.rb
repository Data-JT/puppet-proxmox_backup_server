# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_notification_target resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsNotificationTarget::PbsNotificationTarget < Puppet::Provider::PbsNotificationTarget::ProxmoxBackupServer
end
