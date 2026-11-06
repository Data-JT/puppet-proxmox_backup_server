# frozen_string_literal: true

require 'spec_helper'

# Every type whose PBS endpoint accepts a `delete` parameter on update exposes
# delete_properties, and declares custom_insync so the provider's comparison
# runs at all: without it the attribute would never be in sync.
TYPES_WITH_DELETE_PROPERTIES = {
  pbs_api_token:            { tokenid: 'puppet@pbs!ci' },
  pbs_datastore:            { name: 'backup', path: '/mnt/backup' },
  pbs_node_config:          { node: 'pbs' },
  pbs_notification_matcher: { name: 'errors' },
  pbs_notification_target:  { name: 'mail', type: 'sendmail' },
  pbs_prune_job:            { id: 'prune', store: 'backup', job_schedule: 'daily' },
  pbs_realm:                { realm: 'corp', type: 'ldap' },
  pbs_remote:               { name: 'offsite' },
  pbs_s3_endpoint:          { id: 's3' },
  pbs_sync_job:             { id: 'sync', store: 'backup', remote_store: 'backup' },
  pbs_user:                 { userid: 'backup@pbs' },
  pbs_verification_job:     { id: 'verify', store: 'backup' },
}.freeze

RSpec.describe 'delete_properties' do
  TYPES_WITH_DELETE_PROPERTIES.each do |type_name, title_attributes|
    describe type_name.to_s do
      let(:type) do
        require "puppet/type/#{type_name}"
        Puppet::Type.type(type_name)
      end

      it 'declares custom_insync so the provider decides when the deletion is done' do
        expect(type.context.type.feature?('custom_insync')).to be(true)
      end

      it 'accepts PBS API property names to remove' do
        resource = type.new(title_attributes.merge(delete_properties: ['comment']))
        expect(resource[:delete_properties]).to eq(['comment'])
      end

      it 'rejects a non-array value' do
        expect { type.new(title_attributes.merge(delete_properties: 'comment')) }.to raise_error(Puppet::ResourceError)
      end
    end
  end

  describe 'pbs_api_token' do
    let(:type) do
      require 'puppet/type/pbs_api_token'
      Puppet::Type.type(:pbs_api_token)
    end

    it 'rejects properties other than comment, which PBS cannot delete on tokens' do
      expect { type.new(tokenid: 'puppet@pbs!ci', delete_properties: ['expire']) }.to raise_error(Puppet::ResourceError)
    end
  end
end
