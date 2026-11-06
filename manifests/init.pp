# @summary Configures the PBS transport credentials on the node running the Puppet agent.
#
# Writes a YAML file that the proxmox_backup_server providers read at runtime
# to authenticate against the local PBS REST API. Declare this class on every
# PBS node before declaring any pbs_* resources.
#
# @example Configure providers for the local PBS API
#   class { 'proxmox_backup_server':
#     token_id     => 'root@pam!puppet',
#     token_secret => Sensitive(lookup('pbs::token_secret')),
#   }
#
# @param token_id
#   API token ID (format: user@realm!tokenname, e.g. root@pam!puppet).
# @param token_secret
#   API token secret. Wrapped in Sensitive; never written to Puppet reports.
# @param host
#   PBS hostname or IP. Defaults to localhost (the PBS API on the same node).
# @param port
#   PBS API port. Defaults to 8007.
# @param ssl_verify
#   Whether to verify the PBS TLS certificate.
# @param ssl_ca_file
#   Absolute path to a CA certificate file when ssl_verify is true and PBS uses a private CA.
# @param task_timeout
#   Seconds to wait for PBS background tasks (e.g. datastore creation) before
#   the providers give up. Defaults to 60 when unset.
# @param config_file
#   Absolute path where the transport config YAML is written.
#   A symlink is created at the provider discovery path when this differs.
#   Defaults to the agent's own confdir (fact `proxmox_backup_server_confdir`), which is where
#   the providers look; the compiling server's confdir may differ.
class proxmox_backup_server (
  Pattern[/\A[^@!\s]+@[^@!\s]+![^!\s]+\z/] $token_id,
  Sensitive[String]                        $token_secret,
  String                                   $host        = 'localhost',
  Integer                                  $port        = 8007,
  Boolean                                  $ssl_verify  = true,
  Optional[Pattern[/\A\//]]                $ssl_ca_file = undef,
  Optional[Integer]                        $task_timeout = undef,
  # The agent's confdir, from the proxmox_backup_server_confdir fact: the
  # providers read Puppet.settings[:confdir] on the node, while
  # $settings::confdir here is the COMPILING server's, which differs when
  # server and agent use different layouts (AIO server, Debian agent).
  # $settings::confdir only before the fact has been pluginsynced.
  Pattern[/\A\//]                          $config_file = "${$facts['proxmox_backup_server_confdir'].lest || { $settings::confdir }}/pbs_transport.yaml",
) {
  file { $config_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => Sensitive(epp('proxmox_backup_server/pbs_transport.epp', {
          'host'         => $host,
          'port'         => $port,
          'token_id'     => $token_id,
          'token_secret' => $token_secret.unwrap,
          'ssl_verify'   => $ssl_verify,
          'ssl_ca_file'  => $ssl_ca_file,
          'task_timeout' => $task_timeout,
    })),
  }

  $provider_config_file = "${$facts['proxmox_backup_server_confdir'].lest || { $settings::confdir }}/pbs_transport.yaml"
  if $config_file != $provider_config_file {
    file { $provider_config_file:
      ensure  => link,
      target  => $config_file,
      require => File[$config_file],
    }
  }
}
