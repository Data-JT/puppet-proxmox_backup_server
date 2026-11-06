# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_s3_endpoint/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsS3Endpoint::ProxmoxBackupServer do
  subject(:provider) { described_class.new }

  let(:mock_transport) { instance_double('Puppet::Transport::ProxmoxBackupServer') }
  let(:mock_type)      { instance_double('Puppet::ResourceApi::Type') }
  let(:context) do
    instance_double(
      'Puppet::ResourceApi::BaseContext',
      type: mock_type,
    )
  end

  let(:store) { PuppetX::ProxmoxBackupServer::SecretStore }

  before(:each) do
    # No example touches a real /etc/proxmox-backup; s3.cfg is stubbed.
    allow(store).to receive_messages(available?: true, s3_secret_key: nil)
    allow(provider).to receive(:pbs_transport).and_return(mock_transport)
    allow(mock_type).to receive(:namevars).and_return([:id])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
  end

  describe '#get' do
    it 'returns [] when the API returns nil' do
      allow(mock_transport).to receive(:get).with(context, '/config/s3', any_args).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the API returns an empty array' do
      allow(mock_transport).to receive(:get).with(context, '/config/s3', any_args).and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'maps the API response to Puppet resource hashes' do
      api_data = [{
        'id'         => 'aws-primary',
        'endpoint'   => 'https://s3.amazonaws.com',
        'access-key' => 'AKIAIOSFODNN7EXAMPLE',
        'region'     => 'us-east-1',
        'port'       => 443,
        'path-style' => false,
        'comment'    => 'Primary AWS bucket',
      }]
      allow(mock_transport).to receive(:get).with(context, '/config/s3', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          id:         'aws-primary',
          endpoint:   'https://s3.amazonaws.com',
          access_key: 'AKIAIOSFODNN7EXAMPLE',
          region:     'us-east-1',
          port:       443,
          path_style: false,
          ensure:     'present',
        ),
      )
    end

    it 'does not include secret_key in returned hashes' do
      api_data = [{ 'id' => 'ep', 'endpoint' => 'https://s3.example.com', 'access-key' => 'AK' }]
      allow(mock_transport).to receive(:get).with(context, '/config/s3', any_args).and_return(api_data)
      expect(provider.get(context).first).not_to have_key(:secret_key)
    end

    it 'maps path-style boolean true' do
      api_data = [{ 'id' => 'ep', 'endpoint' => 'https://s3.example.com', 'access-key' => 'AK', 'path-style' => true }]
      allow(mock_transport).to receive(:get).with(context, '/config/s3', any_args).and_return(api_data)
      expect(provider.get(context).first[:path_style]).to be(true)
    end

    it 'maps rate and burst fields as HumanByte strings' do
      api_data = [{
        'id' => 'ep', 'endpoint' => 'https://s3.example.com', 'access-key' => 'AK',
        'rate-in' => '100 MiB', 'burst-in' => '200 MiB',
        'rate-out' => '50 MiB', 'burst-out' => '104857600',
      }]
      allow(mock_transport).to receive(:get).with(context, '/config/s3', any_args).and_return(api_data)

      result = provider.get(context).first
      expect(result[:rate_in]).to eq('100 MiB')
      expect(result[:burst_in]).to eq('200 MiB')
      expect(result[:rate_out]).to eq('50 MiB')
      expect(result[:burst_out]).to eq('104857600')
    end

    it 'maps access-key using kebab-to-underscore translation' do
      api_data = [{ 'id' => 'ep', 'endpoint' => 'https://s3.example.com', 'access-key' => 'MYKEY' }]
      allow(mock_transport).to receive(:get).with(context, '/config/s3', any_args).and_return(api_data)
      expect(provider.get(context).first[:access_key]).to eq('MYKEY')
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end
  end

  describe '#create' do
    it 'posts to /config/s3' do
      should = { id: 'aws-primary', endpoint: 'https://s3.amazonaws.com', access_key: 'AK',
                 secret_key: 'sk', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, _body|
        expect(path).to eq('/config/s3')
      end
      provider.create(context, 'aws-primary', should)
    end

    it 'includes secret-key in the POST body' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('mysecret')
      should = { id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK',
                 secret_key: sensitive, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('secret-key' => 'mysecret')
      end
      provider.create(context, 'ep', should)
    end

    it 'includes access-key (hyphenated) in the POST body' do
      should = { id: 'ep', endpoint: 'https://s3.example.com', access_key: 'MYKEY',
                 secret_key: 'sk', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('access-key' => 'MYKEY')
        expect(body).not_to have_key('access_key')
      end
      provider.create(context, 'ep', should)
    end

    it 'excludes ensure from the POST body' do
      should = { id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK',
                 secret_key: 'sk', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'ep', should)
    end

    it 'excludes nil optional attributes from the POST body' do
      should = { id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK',
                 secret_key: 'sk', ensure: 'present', port: nil, region: nil, fingerprint: nil }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('port')
        expect(body).not_to have_key('region')
        expect(body).not_to have_key('fingerprint')
      end
      provider.create(context, 'ep', should)
    end

    it 'raises when creating without a secret_key' do
      should = { id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK', ensure: 'present' }
      expect(mock_transport).not_to receive(:post)
      expect { provider.create(context, 'ep', should) }
        .to raise_error(Puppet::ResourceError, %r{secret_key is required when creating})
    end

    it 'sends path-style boolean correctly' do
      should = { id: 'ep', endpoint: 'https://minio.example.com', access_key: 'AK',
                 secret_key: 'sk', ensure: 'present', path_style: :true }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['path-style']).to eq(true)
      end
      provider.create(context, 'ep', should)
    end
  end

  describe '#update' do
    it 'puts to /config/s3/{id}' do
      should = { id: 'aws-primary', endpoint: 'https://s3.amazonaws.com', access_key: 'AK',
                 secret_key: 'sk', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/config/s3/aws-primary')
      end
      provider.update(context, 'aws-primary', should)
    end

    it 'excludes id and ensure from the PUT body' do
      should = { id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK',
                 secret_key: 'sk', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('id')
        expect(body).not_to have_key('ensure')
      end
      provider.update(context, 'ep', should)
    end

    # PBS keeps a secret that a PUT omits, so an unchanged key must not be
    # resent: doing so rewrote the stored value on every run.
    it 'omits secret-key when it already matches s3.cfg' do
      allow(store).to receive(:s3_secret_key).with('ep').and_return('newsecret')
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('newsecret')
      should = { id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK',
                 secret_key: sensitive, ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('secret-key')
      end
      provider.update(context, 'ep', should)
    end

    it 'includes secret-key when it differs from s3.cfg' do
      allow(store).to receive(:s3_secret_key).with('ep').and_return('stale')
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('newsecret')
      should = { id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK',
                 secret_key: sensitive, ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('secret-key' => 'newsecret')
      end
      provider.update(context, 'ep', should)
    end

    it 'uses hyphenated PBS keys in the PUT body' do
      should = { id: 'ep', endpoint: 'https://s3.example.com', access_key: 'MYKEY',
                 secret_key: 'sk', region: 'eu-west-1', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('access-key' => 'MYKEY', 'region' => 'eu-west-1')
        expect(body).not_to have_key('access_key')
      end
      provider.update(context, 'ep', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /config/s3/{id}' do
      expect(mock_transport).to receive(:delete).with(context, '/config/s3/aws-primary')
      provider.delete(context, 'aws-primary')
    end
  end
end
