# frozen_string_literal: true

require 'spec_helper'

# Puppet::Type.validate is `define_method(:validate, &block)` (type.rb:2250):
# declaring one REPLACES the Resource API's own validate rather than chaining.
# The Resource API's validate is where @missing_attrs is initialised, and
# retrieve unconditionally calls raise_missing_attrs, which builds its message
# with @missing_attrs.join *before* checking the guard (resource_api.rb:376).
#
# So a single `validate do` block anywhere in this module makes *every* resource
# of that type fail with "undefined method `join' for nil" during any real
# catalog run -- while the unit suite stays green, because specs rarely call
# retrieve. pbs_user shipped exactly that bug.
#
# This guards every type at once.
RSpec.describe 'Resource API validate hook' do
  minimal = {
    pbs_acl: { title: '/datastore/backup|svc@pbs|DatastoreBackup', acl_path: '/datastore/backup',
               ugid: 'svc@pbs', role: 'DatastoreBackup' },
    pbs_api_token: { tokenid: 'svc@pbs!ci' },
    pbs_datastore: { name: 'backup' },
    pbs_node_config: { node: 'localhost' },
    pbs_notification_matcher: { name: 'default' },
    pbs_notification_target: { name: 'relay', type: 'smtp' },
    pbs_prune_job: { id: 'prune-daily' },
    pbs_realm: { realm: 'corp', type: 'ldap' },
    pbs_remote: { name: 'offsite', host: 'pbs.example.com', userid: 'sync@pbs' },
    pbs_s3_endpoint: { id: 'minio', endpoint: 'https://s3.example.com', access_key: 'AK' },
    pbs_sync_job: { id: 'sync-nightly' },
    pbs_user: { userid: 'svc@pbs' },
    pbs_verification_job: { id: 'verify-weekly' },
  }.freeze

  minimal.each do |type_name, attributes|
    describe type_name do
      let(:resource) do
        require "puppet/type/#{type_name}"
        Puppet::Type.type(type_name).new(attributes)
      end

      it 'initialises @missing_attrs, so the Resource API validate hook is intact' do
        expect(resource.instance_variable_get(:@missing_attrs)).to be_an(Array)
      end

      # The exact call retrieve makes, and the one that crashed.
      it 'builds the missing-attribute message without raising' do
        expect { resource.send(:raise_missing_attrs) }.not_to raise_error
      end
    end
  end

  it 'covers every type the module ships' do
    shipped = Dir[File.join(__dir__, '..', '..', '..', '..', 'lib', 'puppet', 'type', 'pbs_*.rb')]
              .map { |path| File.basename(path, '.rb').to_sym }
              .reject { |name| [:pbs_transport_autorequire, :pbs_sensitive_parameters].include?(name) }
    expect(shipped).to match_array(minimal.keys)
  end
end
