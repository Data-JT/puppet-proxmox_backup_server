# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_api_token/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsApiToken::ProxmoxBackupServer do
  subject(:provider) { described_class.new }

  let(:mock_transport) { instance_double('Puppet::Transport::ProxmoxBackupServer') }
  let(:mock_type)      { instance_double('Puppet::ResourceApi::Type') }
  let(:context) do
    instance_double(
      'Puppet::ResourceApi::BaseContext',
      type: mock_type,
    )
  end

  before(:each) do
    allow(provider).to receive(:pbs_transport).and_return(mock_transport)
    allow(mock_type).to receive(:namevars).and_return([:tokenid])
    allow(context).to receive(:notice)
    allow(context).to receive(:warning)
    allow(context).to receive(:err)
  end

  describe '#get' do
    it 'returns [] when there are no users' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args).and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the users endpoint returns nil' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when a user has no tokens' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'puppet@pbs' }])
      allow(mock_transport).to receive(:get).with(context, '/access/users/puppet@pbs/token', any_args)
                                            .and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'maps a token to a Puppet resource hash' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'puppet@pbs' }])
      allow(mock_transport).to receive(:get).with(context, '/access/users/puppet@pbs/token', any_args)
                                            .and_return([
                                                          {
                                                            'tokenid' => 'puppet@pbs!mytoken',
                                                            'comment' => 'automation',
                                                            'enable'  => true,
                                                            'expire'  => 0,
                                                          },
                                                        ])

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          tokenid: 'puppet@pbs!mytoken',
          comment: 'automation',
          enable:  true,
          expire:  0,
          ensure:  'present',
        ),
      )
    end

    it 'queries the token endpoint for every user' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'puppet@pbs' }, { 'userid' => 'root@pam' }])
      expect(mock_transport).to receive(:get).with(context, '/access/users/puppet@pbs/token', any_args).and_return([])
      expect(mock_transport).to receive(:get).with(context, '/access/users/root@pam/token', any_args).and_return([])
      provider.get(context)
    end

    it 'aggregates tokens from multiple users' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'puppet@pbs' }, { 'userid' => 'root@pam' }])
      allow(mock_transport).to receive(:get).with(context, '/access/users/puppet@pbs/token', any_args)
                                            .and_return([{ 'tokenid' => 'puppet@pbs!tok1' }])
      allow(mock_transport).to receive(:get).with(context, '/access/users/root@pam/token', any_args)
                                            .and_return([{ 'tokenid' => 'root@pam!tok2' }])

      expect(provider.get(context).length).to eq(2)
    end

    it 'converts enable true' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'puppet@pbs' }])
      allow(mock_transport).to receive(:get).with(context, '/access/users/puppet@pbs/token', any_args)
                                            .and_return([{ 'tokenid' => 'puppet@pbs!tok', 'enable' => true }])
      expect(provider.get(context).first[:enable]).to be(true)
    end

    it 'converts enable false' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'puppet@pbs' }])
      allow(mock_transport).to receive(:get).with(context, '/access/users/puppet@pbs/token', any_args)
                                            .and_return([{ 'tokenid' => 'puppet@pbs!tok', 'enable' => false }])
      expect(provider.get(context).first[:enable]).to be(false)
    end

    it 'normalizes a missing enable field to true (PBS default)' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'puppet@pbs' }])
      allow(mock_transport).to receive(:get).with(context, '/access/users/puppet@pbs/token', any_args)
                                            .and_return([{ 'tokenid' => 'puppet@pbs!tok' }])
      expect(provider.get(context).first[:enable]).to be(true)
    end

    it 'does not override an explicit enable false' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'puppet@pbs' }])
      allow(mock_transport).to receive(:get).with(context, '/access/users/puppet@pbs/token', any_args)
                                            .and_return([{ 'tokenid' => 'puppet@pbs!tok', 'enable' => 0 }])
      expect(provider.get(context).first[:enable]).to be(false)
    end

    it 'handles nil token list for a user' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'puppet@pbs' }])
      allow(mock_transport).to receive(:get).with(context, '/access/users/puppet@pbs/token', any_args)
                                            .and_return(nil)
      expect(provider.get(context)).to eq([])
    end
  end

  describe '#create' do
    it 'never sends a delete parameter on create even when delete_properties are declared' do
      should = { tokenid: 'puppet@pbs!mytoken', comment: 'ci', delete_properties: ['comment'], ensure: 'present' }
      expect(mock_transport).to receive(:post)
        .with(context, '/access/users/puppet@pbs/token/mytoken', { 'comment' => 'ci' })
        .and_return(nil)
      provider.create(context, 'puppet@pbs!mytoken', should)
    end

    it 'stores the one-time generated secret with mode 0600' do
      secret_file = Tempfile.new('pbs-token')
      secret_path = secret_file.path
      secret_file.close
      allow(mock_transport).to receive(:post).and_return('value' => 'generated-secret')

      provider.create(
        context,
        'puppet@pbs!mytoken',
        tokenid: 'puppet@pbs!mytoken', secret_file: secret_path, ensure: 'present',
      )

      expect(File.read(secret_path)).to eq("generated-secret\n")
      expect(File.stat(secret_path).mode & 0o777).to eq(0o600)
    ensure
      File.delete(secret_path) if secret_path && File.exist?(secret_path)
    end

    it 'warns and discards the secret when no secret_file is configured' do
      allow(mock_transport).to receive(:post).and_return('value' => 'generated-secret')
      expect(context).to receive(:warning).with(%r{secret_file is not configured})

      provider.create(context, 'puppet@pbs!mytoken', tokenid: 'puppet@pbs!mytoken', ensure: 'present')
    end

    it 'posts to /access/users/{userid}/token/{tokenname}' do
      should = { tokenid: 'puppet@pbs!mytoken', comment: 'test', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/access/users/puppet@pbs/token/mytoken')
        expect(body).to include('comment' => 'test')
      end
      provider.create(context, 'puppet@pbs!mytoken', should)
    end

    it 'does not include tokenid in the POST body' do
      should = { tokenid: 'puppet@pbs!mytoken', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('tokenid')
      end
      provider.create(context, 'puppet@pbs!mytoken', should)
    end

    it 'does not include ensure in the POST body' do
      should = { tokenid: 'puppet@pbs!mytoken', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'puppet@pbs!mytoken', should)
    end

    it 'does not include secret_file in the POST body' do
      should = { tokenid: 'puppet@pbs!mytoken', secret_file: '/tmp/token.secret', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('secret_file')
      end
      provider.create(context, 'puppet@pbs!mytoken', should)
    end

    it 'excludes nil optional attributes from the POST body' do
      should = { tokenid: 'puppet@pbs!mytoken', comment: nil, expire: nil, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('comment')
        expect(body).not_to have_key('expire')
      end
      provider.create(context, 'puppet@pbs!mytoken', should)
    end

    it 'raises an error for an invalid tokenid' do
      should = { tokenid: 'bad-format', ensure: 'present' }
      expect { provider.create(context, 'bad-format', should) }
        .to raise_error(Puppet::ResourceError, %r{user@realm!tokenname})
    end

    it 'raises an error when the tokenname part is missing' do
      should = { tokenid: 'puppet@pbs!', ensure: 'present' }
      expect { provider.create(context, 'puppet@pbs!', should) }
        .to raise_error(Puppet::ResourceError, %r{user@realm!tokenname})
    end
  end

  describe '#update' do
    it 'sends delete_properties as the PBS delete list' do
      should = { tokenid: 'puppet@pbs!mytoken', delete_properties: ['comment'], ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to eq('delete' => ['comment'])
      end
      provider.update(context, 'puppet@pbs!mytoken', should)
    end

    it 'puts to /access/users/{userid}/token/{tokenname}' do
      should = { tokenid: 'puppet@pbs!mytoken', comment: 'updated', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/access/users/puppet@pbs/token/mytoken')
      end
      provider.update(context, 'puppet@pbs!mytoken', should)
    end

    it 'does not include tokenid in the PUT body' do
      should = { tokenid: 'puppet@pbs!mytoken', comment: 'updated', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('tokenid')
        expect(body).to include('comment' => 'updated')
      end
      provider.update(context, 'puppet@pbs!mytoken', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /access/users/{userid}/token/{tokenname}' do
      expect(mock_transport).to receive(:delete)
        .with(context, '/access/users/puppet@pbs/token/mytoken')
      provider.delete(context, 'puppet@pbs!mytoken')
    end

    it 'parses pam realm tokens correctly' do
      expect(mock_transport).to receive(:delete)
        .with(context, '/access/users/root@pam/token/admin-token')
      provider.delete(context, 'root@pam!admin-token')
    end
  end
end
