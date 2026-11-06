# @summary Declares PBS resources from Hiera data.
#
# Include this class after `proxmox_backup_server` when adopting an existing
# PBS node or when you prefer data-driven resource declarations.
#
# @example Declare resources from Hiera
#   include proxmox_backup_server::resources
#
# @param datastores
#   Hash of `pbs_datastore` resources, keyed by datastore name.
# @param users
#   Hash of `pbs_user` resources, keyed by user ID.
# @param acls
#   Hash of `pbs_acl` resources, keyed as `path|ugid|role`.
# @param remotes
#   Hash of `pbs_remote` resources, keyed by remote name.
# @param sync_jobs
#   Hash of `pbs_sync_job` resources, keyed by job ID.
# @param prune_jobs
#   Hash of `pbs_prune_job` resources, keyed by job ID.
# @param verification_jobs
#   Hash of `pbs_verification_job` resources, keyed by job ID.
# @param notification_targets
#   Hash of `pbs_notification_target` resources, keyed by target name.
# @param notification_matchers
#   Hash of `pbs_notification_matcher` resources, keyed by matcher name.
# @param api_tokens
#   Hash of `pbs_api_token` resources, keyed by full token ID (user@realm!tokenname).
# @param realms
#   Hash of `pbs_realm` resources, keyed by realm name.
# @param s3_endpoints
#   Hash of `pbs_s3_endpoint` resources, keyed by endpoint ID.
# @param node_config
#   Hash of `pbs_node_config` resources, keyed by the node's short hostname
#   (must match the PBS host's local hostname).
class proxmox_backup_server::resources (
  Hash[String, Hash] $datastores             = {},
  Hash[String, Hash] $users                  = {},
  Hash[String, Hash] $acls                   = {},
  Hash[String, Hash] $remotes                = {},
  Hash[String, Hash] $sync_jobs              = {},
  Hash[String, Hash] $prune_jobs             = {},
  Hash[String, Hash] $verification_jobs      = {},
  Hash[String, Hash] $notification_targets   = {},
  Hash[String, Hash] $notification_matchers  = {},
  Hash[String, Hash] $api_tokens             = {},
  Hash[String, Hash] $realms                 = {},
  Hash[String, Hash] $s3_endpoints           = {},
  Hash[String, Hash] $node_config            = {},
) {
  $datastores.each |String $title, Hash $attributes| {
    pbs_datastore { $title:
      * => $attributes,
    }
  }

  $users.each |String $title, Hash $attributes| {
    pbs_user { $title:
      * => $attributes,
    }
  }

  $acls.each |String $title, Hash $attributes| {
    pbs_acl { $title:
      * => $attributes,
    }
  }

  $remotes.each |String $title, Hash $attributes| {
    pbs_remote { $title:
      * => $attributes,
    }
  }

  $sync_jobs.each |String $title, Hash $attributes| {
    pbs_sync_job { $title:
      * => $attributes,
    }
  }

  $prune_jobs.each |String $title, Hash $attributes| {
    pbs_prune_job { $title:
      * => $attributes,
    }
  }

  $verification_jobs.each |String $title, Hash $attributes| {
    pbs_verification_job { $title:
      * => $attributes,
    }
  }

  $notification_targets.each |String $title, Hash $attributes| {
    pbs_notification_target { $title:
      * => $attributes,
    }
  }

  $notification_matchers.each |String $title, Hash $attributes| {
    pbs_notification_matcher { $title:
      * => $attributes,
    }
  }

  $api_tokens.each |String $title, Hash $attributes| {
    pbs_api_token { $title:
      * => $attributes,
    }
  }

  $realms.each |String $title, Hash $attributes| {
    pbs_realm { $title:
      * => $attributes,
    }
  }

  $s3_endpoints.each |String $title, Hash $attributes| {
    pbs_s3_endpoint { $title:
      * => $attributes,
    }
  }

  $node_config.each |String $title, Hash $attributes| {
    pbs_node_config { $title:
      * => $attributes,
    }
  }

  # Order related resources only when both are managed by this Hiera class.
  $users.each |String $title, Hash $attributes| {
    $realm = $title.split('@')[-1]
    if $realm in $realms {
      Pbs_realm[$realm] -> Pbs_user[$title]
    }
  }

  $api_tokens.each |String $title, Hash $attributes| {
    $userid = $title.split('!')[0]
    if $userid in $users {
      Pbs_user[$userid] -> Pbs_api_token[$title]
    }
  }

  $acls.each |String $title, Hash $attributes| {
    $ugid = $title.split('[|]')[1]
    if $ugid in $users {
      Pbs_user[$ugid] -> Pbs_acl[$title]
    }
    if $ugid in $api_tokens {
      Pbs_api_token[$ugid] -> Pbs_acl[$title]
    }
  }

  $sync_jobs.each |String $title, Hash $attributes| {
    $store = $attributes['store']
    $remote = $attributes['remote']
    if $store in $datastores {
      Pbs_datastore[$store] -> Pbs_sync_job[$title]
    }
    if $remote and $remote in $remotes {
      Pbs_remote[$remote] -> Pbs_sync_job[$title]
    }
  }

  $prune_jobs.each |String $title, Hash $attributes| {
    $store = $attributes['store']
    if $store in $datastores {
      Pbs_datastore[$store] -> Pbs_prune_job[$title]
    }
  }

  $verification_jobs.each |String $title, Hash $attributes| {
    $store = $attributes['store']
    if $store in $datastores {
      Pbs_datastore[$store] -> Pbs_verification_job[$title]
    }
  }

  $notification_matchers.each |String $title, Hash $attributes| {
    if $attributes['target'] {
      $attributes['target'].each |String $target| {
        if $target in $notification_targets {
          Pbs_notification_target[$target] -> Pbs_notification_matcher[$title]
        }
      }
    }
  }
}
