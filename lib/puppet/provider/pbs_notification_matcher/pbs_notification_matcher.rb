# frozen_string_literal: true

require_relative 'proxmox_backup_server'

# Default provider for pbs_notification_matcher resources. Delegates to ProxmoxBackupServer.
class Puppet::Provider::PbsNotificationMatcher::PbsNotificationMatcher < Puppet::Provider::PbsNotificationMatcher::ProxmoxBackupServer
end
