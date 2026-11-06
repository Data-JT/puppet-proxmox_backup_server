# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_remote/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsRemote::ProxmoxBackupServer do
  subject(:provider) { described_class.new }

  let(:mock_transport) { instance_double('Puppet::Transport::ProxmoxBackupServer') }
  let(:mock_type)      { instance_double('Puppet::ResourceApi::Type') }
  let(:context) do
    instance_double(
      'Puppet::ResourceApi::BaseContext',
      type: mock_type,
    )
  end
  let(:sensitive_password) { Puppet::Pops::Types::PSensitiveType::Sensitive.new('hunter2') }

  let(:store) { PuppetX::ProxmoxBackupServer::SecretStore }

  before(:each) do
    # No example touches a real /etc/proxmox-backup; remote.cfg is stubbed.
    allow(store).to receive_messages(available?: true, remote_password: nil)
    allow(provider).to receive(:pbs_transport).and_return(mock_transport)
    allow(mock_type).to receive(:namevars).and_return([:name])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
  end

  describe '#get' do
    it 'returns [] when the API returns nil' do
      allow(mock_transport).to receive(:get).with(context, '/config/remote', any_args).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the API returns an empty array' do
      allow(mock_transport).to receive(:get).with(context, '/config/remote', any_args).and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'maps the API response to Puppet resource hashes' do
      api_data = [
        {
          'name'        => 'myremote',
          'host'        => 'pbs.example.com',
          'port'        => 8007,
          'auth-id'     => 'user@pbs',
          'fingerprint' => 'AA:BB:CC',
          'comment'     => 'test remote',
        },
      ]
      allow(mock_transport).to receive(:get).with(context, '/config/remote', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          name:        'myremote',
          host:        'pbs.example.com',
          port:        8007,
          userid:      'user@pbs',
          fingerprint: 'AA:BB:CC',
          comment:     'test remote',
          ensure:      'present',
        ),
      )
    end

    it 'does not include password in returned hashes' do
      api_data = [{ 'name' => 'myremote', 'host' => 'pbs.example.com', 'auth-id' => 'user@pbs' }]
      allow(mock_transport).to receive(:get).with(context, '/config/remote', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result.first).not_to have_key(:password)
    end

    it 'maps use-node-proxy boolean true' do
      api_data = [{ 'name' => 'r', 'host' => 'h', 'auth-id' => 'u@pbs', 'use-node-proxy' => true }]
      allow(mock_transport).to receive(:get).with(context, '/config/remote', any_args).and_return(api_data)
      expect(provider.get(context).first[:use_node_proxy]).to be(true)
    end

    it 'maps use-node-proxy boolean false' do
      api_data = [{ 'name' => 'r', 'host' => 'h', 'auth-id' => 'u@pbs', 'use-node-proxy' => false }]
      allow(mock_transport).to receive(:get).with(context, '/config/remote', any_args).and_return(api_data)
      expect(provider.get(context).first[:use_node_proxy]).to be(false)
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end
  end

  describe '#create' do
    it 'posts to /config/remote' do
      should = { name: 'myremote', host: 'pbs.example.com', userid: 'user@pbs', password: sensitive_password, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, _body|
        expect(path).to eq('/config/remote')
      end
      provider.create(context, 'myremote', should)
    end

    it 'includes password (unwrapped) in the POST body' do
      should = { name: 'myremote', host: 'pbs.example.com', userid: 'user@pbs', password: sensitive_password, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('password' => 'hunter2')
      end
      provider.create(context, 'myremote', should)
    end

    it 'excludes ensure from the POST body' do
      should = { name: 'myremote', host: 'pbs.example.com', userid: 'user@pbs', password: sensitive_password, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'myremote', should)
    end

    it 'excludes nil attributes from the POST body' do
      should = { name: 'myremote', host: 'pbs.example.com', userid: 'user@pbs', password: sensitive_password,
                 ensure: 'present', port: nil, fingerprint: nil, comment: nil }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('port')
        expect(body).not_to have_key('fingerprint')
        expect(body).not_to have_key('comment')
      end
      provider.create(context, 'myremote', should)
    end
  end

  describe '#update' do
    it 'sends delete_properties as the PBS delete list' do
      should = { name: 'myremote', delete_properties: ['comment', 'fingerprint'], ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to eq('delete' => ['comment', 'fingerprint'])
      end
      provider.update(context, 'myremote', should)
    end

    it 'puts to /config/remote/{name}' do
      should = { name: 'myremote', host: 'pbs.example.com', userid: 'user@pbs', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/config/remote/myremote')
      end
      provider.update(context, 'myremote', should)
    end

    # PBS keeps a secret that a PUT omits, so an unchanged password must not
    # be resent: doing so rewrote the stored value and minted a change event
    # on every run.
    it 'omits the password when it already matches remote.cfg' do
      allow(store).to receive(:remote_password).with('myremote').and_return('hunter2')
      should = { name: 'myremote', host: 'pbs.example.com', userid: 'user@pbs',
                 password: sensitive_password, ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('password')
      end
      provider.update(context, 'myremote', should)
    end

    it 'includes the password when it differs from remote.cfg' do
      allow(store).to receive(:remote_password).with('myremote').and_return('stale')
      should = { name: 'myremote', host: 'pbs.example.com', userid: 'user@pbs',
                 password: sensitive_password, ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('password' => 'hunter2')
      end
      provider.update(context, 'myremote', should)
    end

    it 'includes the password when PBS holds none yet' do
      allow(store).to receive(:remote_password).with('myremote').and_return(nil)
      should = { name: 'myremote', host: 'pbs.example.com', userid: 'user@pbs',
                 password: sensitive_password, ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('password' => 'hunter2')
      end
      provider.update(context, 'myremote', should)
    end

    it 'excludes name and ensure from the PUT body' do
      should = { name: 'myremote', host: 'pbs.example.com', userid: 'user@pbs', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('name')
        expect(body).not_to have_key('ensure')
      end
      provider.update(context, 'myremote', should)
    end

    it 'includes non-password attributes in the PUT body' do
      should = { name: 'myremote', host: 'pbs.example.com', userid: 'user@pbs',
                 comment: 'updated', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('host' => 'pbs.example.com', 'auth-id' => 'user@pbs', 'comment' => 'updated')
      end
      provider.update(context, 'myremote', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /config/remote/{name}' do
      expect(mock_transport).to receive(:delete).with(context, '/config/remote/myremote')
      provider.delete(context, 'myremote')
    end
  end
end
