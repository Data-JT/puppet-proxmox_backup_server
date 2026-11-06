# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_acl/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsAcl::ProxmoxBackupServer do
  subject(:provider) { described_class.new }

  let(:mock_transport) { instance_double('Puppet::Transport::ProxmoxBackupServer') }
  let(:mock_type)      { instance_double('Puppet::ResourceApi::Type') }
  let(:context) do
    instance_double(
      'Puppet::ResourceApi::BaseContext',
      type: mock_type,
    )
  end

  # Fixture: PBS returns a flat array of ACL entries; each entry carries path,
  # ugid, roleid, propagate, and type directly. This fixture has three entries:
  # two under '/' and one under '/datastore/local'.
  let(:acl_entries) do
    [
      { 'path' => '/', 'ugid' => 'admin@pbs', 'roleid' => 'Admin', 'propagate' => 1, 'type' => 'user' },
      { 'path' => '/', 'ugid' => 'audit@pbs', 'roleid' => 'Audit', 'propagate' => 0, 'type' => 'user' },
      { 'path' => '/datastore/local', 'ugid' => 'backup@pbs', 'roleid' => 'DatastoreBackup', 'propagate' => 1, 'type' => 'user' },
    ]
  end

  before(:each) do
    allow(provider).to receive(:pbs_transport).and_return(mock_transport)
    allow(mock_type).to receive(:namevars).and_return([:acl_path, :ugid, :role])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
  end

  describe '#get' do
    it 'returns [] when the API returns nil' do
      allow(mock_transport).to receive(:get).with(context, '/access/acl', any_args).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the API returns an empty array' do
      allow(mock_transport).to receive(:get).with(context, '/access/acl', any_args).and_return([])
      expect(provider.get(context)).to eq([])
    end

    context 'with flat ACL entries from PBS' do
      before(:each) { allow(mock_transport).to receive(:get).with(context, '/access/acl', any_args).and_return(acl_entries) }

      it 'returns one resource per ACL entry' do
        expect(provider.get(context).size).to eq(3)
      end

      it 'includes all three namevars in every resource' do
        expect(provider.get(context)).to all(include(:acl_path, :ugid, :role))
      end

      it 'sets ensure: present on every resource' do
        expect(provider.get(context)).to all(include(ensure: 'present'))
      end

      it 'correctly maps the root-path Admin entry' do
        expect(provider.get(context)).to include(
          hash_including(acl_path: '/', ugid: 'admin@pbs', role: 'Admin', propagate: true, ensure: 'present'),
        )
      end

      it 'converts propagate integer 1 to true' do
        admin = provider.get(context).find { |r| r[:ugid] == 'admin@pbs' }
        expect(admin[:propagate]).to be(true)
      end

      it 'converts propagate integer 0 to false' do
        audit = provider.get(context).find { |r| r[:ugid] == 'audit@pbs' }
        expect(audit[:propagate]).to be(false)
      end

      it 'correctly maps the /datastore/local entry' do
        expect(provider.get(context)).to include(
          hash_including(acl_path: '/datastore/local', ugid: 'backup@pbs', role: 'DatastoreBackup'),
        )
      end

      it 'accepts the older role response key as a fallback' do
        allow(mock_transport).to receive(:get).with(context, '/access/acl', any_args).and_return(
          [{ 'path' => '/', 'ugid' => 'legacy@pbs', 'role' => 'Audit' }],
        )

        expect(provider.get(context).first[:role]).to eq('Audit')
      end
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end
  end

  describe '#create' do
    let(:name) { { acl_path: '/', ugid: 'newuser@pbs', role: 'DatastoreReader' } }
    let(:should_attrs) do
      { acl_path: '/', ugid: 'newuser@pbs', role: 'DatastoreReader', propagate: :true, ensure: 'present' }
    end

    it 'sends PUT (not POST) to /access/acl' do
      expect(mock_transport).to receive(:put).with(context, '/access/acl', anything)
      expect(mock_transport).not_to receive(:post)
      provider.create(context, name, should_attrs)
    end

    it 'includes path, auth-id, and role in the PUT body' do
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('path' => '/', 'auth-id' => 'newuser@pbs', 'role' => 'DatastoreReader')
      end
      provider.create(context, name, should_attrs)
    end

    it 'sends propagate :true as a boolean' do
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body['propagate']).to eq(true)
      end
      provider.create(context, name, should_attrs)
    end

    it 'sends propagate :false as a boolean' do
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body['propagate']).to eq(false)
      end
      provider.create(context, name, should_attrs.merge(propagate: :false))
    end
  end

  describe '#update' do
    let(:name) { { acl_path: '/', ugid: 'admin@pbs', role: 'Admin' } }
    let(:should_attrs) do
      { acl_path: '/', ugid: 'admin@pbs', role: 'Admin', propagate: :false, ensure: 'present' }
    end

    it 'sends PUT (not POST) to /access/acl' do
      expect(mock_transport).to receive(:put).with(context, '/access/acl', anything)
      provider.update(context, name, should_attrs)
    end

    it 'does not include ensure in the PUT body' do
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
      end
      provider.update(context, name, should_attrs)
    end

    it 'includes path, auth-id, and role from the should hash' do
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('path' => '/', 'auth-id' => 'admin@pbs', 'role' => 'Admin')
      end
      provider.update(context, name, should_attrs)
    end
  end

  describe '#delete' do
    let(:name) { { acl_path: '/', ugid: 'admin@pbs', role: 'Admin' } }

    it 'sends PUT (not HTTP DELETE) to /access/acl' do
      expect(mock_transport).to receive(:put).with(context, '/access/acl', anything)
      expect(mock_transport).not_to receive(:delete)
      provider.delete(context, name)
    end

    it 'includes delete: true in the PUT body' do
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body['delete']).to eq(true)
      end
      provider.delete(context, name)
    end

    it 'includes the identifying fields in the body' do
      name = { acl_path: '/datastore/local', ugid: 'backup@pbs', role: 'DatastoreBackup' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include(
          'path'    => '/datastore/local',
          'auth-id' => 'backup@pbs',
          'role'    => 'DatastoreBackup',
          'delete'  => true,
        )
      end
      provider.delete(context, name)
    end
  end
end
