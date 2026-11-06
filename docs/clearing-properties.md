# Clearing optional properties

How to remove a value on the PBS side, since removing an attribute from a manifest does not.

Removing an attribute from a manifest only stops Puppet managing it; the value stays set on the
PBS side. To clear an optional property, list its PBS API name (the hyphenated name the API uses,
such as `gc-schedule`, not the Puppet attribute name) in `delete_properties`:

```puppet
pbs_datastore { 'backup1':
  delete_properties => ['gc-schedule', 'comment'],
}
```

The provider passes the list to the endpoint's `delete` parameter on update, and only while one of
the named properties is still set, so the resource converges instead of re-sending the deletion on
every run. A name the provider does not map is rejected, because its removal could never be
observed. Create requests never carry the parameter.

The following types support `delete_properties`: `pbs_api_token`, `pbs_datastore`,
`pbs_node_config`, `pbs_notification_matcher`, `pbs_notification_target`, `pbs_prune_job`,
`pbs_realm`, `pbs_remote`, `pbs_s3_endpoint`, `pbs_sync_job`, `pbs_user` and
`pbs_verification_job`. On `pbs_api_token` only `comment` can be removed, and only on PBS 3.4 or
later; older releases reject the `delete` parameter on tokens.
