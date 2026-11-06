# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_acl'

RSpec.describe 'pbs_acl type' do
  let(:type) { Puppet::Type.type(:pbs_acl) }

  # Helper: build a resource using the pipe-separated title pattern.
  def new_acl(path: '/', ugid: 'admin@pbs', role: 'Admin', **attrs)
    type.new(title: "#{path}|#{ugid}|#{role}", **attrs)
  end

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has acl_path, ugid, and role as namevars' do
    expect(type.key_attributes).to include(:acl_path, :ugid, :role)
  end

  describe 'title_patterns' do
    it 'parses a pipe-separated title into all three namevars' do
      resource = type.new(title: '/datastore/local|backup@pbs|DatastoreBackup')
      expect(resource[:acl_path]).to eq('/datastore/local')
      expect(resource[:ugid]).to eq('backup@pbs')
      expect(resource[:role]).to eq('DatastoreBackup')
    end

    it 'treats a plain title as acl_path, with ugid and role supplied separately' do
      resource = type.new(title: '/datastore', ugid: 'user@pbs', role: 'DatastoreAudit')
      expect(resource[:acl_path]).to eq('/datastore')
      expect(resource[:ugid]).to eq('user@pbs')
      expect(resource[:role]).to eq('DatastoreAudit')
    end
  end

  describe 'namevar validation' do
    it 'accepts the root path' do
      expect { new_acl(path: '/') }.not_to raise_error
    end

    it 'accepts a nested datastore path' do
      expect { new_acl(path: '/datastore/backup1') }.not_to raise_error
    end

    it 'accepts an API token authid as ugid' do
      expect { new_acl(ugid: 'automation@pbs!ci') }.not_to raise_error
    end

    it 'rejects a path that does not start with a slash' do
      expect { new_acl(path: 'datastore/backup1') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a path with unsafe characters' do
      expect { new_acl(path: '/datastore/bad path') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a ugid without a realm' do
      expect { new_acl(ugid: 'nobody') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a ugid containing a slash' do
      expect { new_acl(ugid: 'user@pbs/../evil') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = new_acl(ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = new_acl(ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'role attribute' do
    ['Admin', 'Audit', 'DatastoreAdmin', 'DatastoreBackup', 'DatastoreAudit', 'DatastoreReader',
     'RemoteAdmin', 'RemoteAudit', 'TapeAdmin', 'TapeAudit', 'TapeOperator', 'TapeReader'].each do |role|
      it "accepts #{role}" do
        expect { new_acl(role: role) }.not_to raise_error
      end
    end

    it 'rejects an invalid role' do
      expect { new_acl(role: 'SuperAdmin') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'propagate attribute' do
    it 'defaults to true' do
      resource = new_acl
      expect(resource[:propagate]).to eq(:true)
    end

    it 'accepts false' do
      resource = new_acl(propagate: false)
      expect(resource[:propagate]).to eq(:false)
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) { type.new(title: '/datastore/local|backup@pbs|DatastoreBackup', propagate: false) }

    it { expect(resource[:acl_path]).to eq('/datastore/local') }
    it { expect(resource[:ugid]).to eq('backup@pbs') }
    it { expect(resource[:role]).to eq('DatastoreBackup') }
    it { expect(resource[:propagate]).to eq(:false) }
  end
end
