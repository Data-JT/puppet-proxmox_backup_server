# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_notification_target/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsNotificationTarget::ProxmoxBackupServer do
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
    # No example touches a real /etc/proxmox-backup; the priv file is stubbed.
    allow(store).to receive_messages(available?: true, notification_secrets: [])
    allow(provider).to receive(:pbs_transport).and_return(mock_transport)
    allow(mock_type).to receive(:namevars).and_return([:name])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
  end

  def stub_all_empty
    ['sendmail', 'smtp', 'gotify', 'webhook'].each do |t|
      allow(mock_transport).to receive(:get).with(context, "/config/notifications/endpoints/#{t}", any_args).and_return([])
    end
  end

  describe '#get' do
    it 'returns [] when all endpoints return nil' do
      ['sendmail', 'smtp', 'gotify', 'webhook'].each do |t|
        allow(mock_transport).to receive(:get).with(context, "/config/notifications/endpoints/#{t}", any_args).and_return(nil)
      end
      expect(provider.get(context)).to eq([])
    end

    it 'queries all four endpoint types' do
      ['sendmail', 'smtp', 'gotify', 'webhook'].each do |t|
        expect(mock_transport).to receive(:get).with(context, "/config/notifications/endpoints/#{t}", any_args).and_return([])
      end
      provider.get(context)
    end

    it 'maps a sendmail endpoint to a Puppet resource hash' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/sendmail', any_args)
                                            .and_return([{ 'name' => 'mail-admin', 'mailto' => ['admin@example.com'], 'comment' => 'admin mail' }])

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          name:    'mail-admin',
          type:    'sendmail',
          mailto:  ['admin@example.com'],
          comment: 'admin mail',
          ensure:  'present',
        ),
      )
    end

    it 'maps an smtp endpoint including server and from-address' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/smtp', any_args)
                                            .and_return([{ 'name' => 'smtp-relay', 'server' => 'smtp.example.com', 'from-address' => 'pbs@example.com' }])

      result = provider.get(context)
      expect(result.first).to include(
        name:         'smtp-relay',
        type:         'smtp',
        server:       'smtp.example.com',
        from_address: 'pbs@example.com',
      )
    end

    it 'maps a gotify endpoint' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/gotify', any_args)
                                            .and_return([{ 'name' => 'gotify', 'server' => 'https://gotify.example.com' }])

      result = provider.get(context)
      expect(result.first).to include(name: 'gotify', type: 'gotify', server: 'https://gotify.example.com')
    end

    it 'maps a webhook endpoint' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/webhook', any_args)
                                            .and_return([{ 'name' => 'wh', 'url' => 'https://hooks.example.com', 'method' => 'post' }])

      result = provider.get(context)
      expect(result.first).to include(name: 'wh', type: 'webhook', url: 'https://hooks.example.com', http_method: 'post')
    end

    it 'converts disable boolean true' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/sendmail', any_args)
                                            .and_return([{ 'name' => 'x', 'disable' => true }])
      expect(provider.get(context).first[:disable]).to be(true)
    end

    it 'converts disable boolean false' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/sendmail', any_args)
                                            .and_return([{ 'name' => 'x', 'disable' => false }])
      expect(provider.get(context).first[:disable]).to be(false)
    end

    it 'populates the internal type cache for use by delete' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/smtp', any_args)
                                            .and_return([{ 'name' => 'smtp-relay' }])

      provider.get(context)

      expect(mock_transport).to receive(:delete).with(context, '/config/notifications/endpoints/smtp/smtp-relay')
      provider.delete(context, 'smtp-relay')
    end

    it 'merges results from multiple endpoint types' do
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/sendmail', any_args)
                                            .and_return([{ 'name' => 'sm1' }])
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/smtp', any_args)
                                            .and_return([{ 'name' => 'smtp1' }])
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/gotify', any_args)
                                            .and_return([])
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/webhook', any_args)
                                            .and_return([])

      expect(provider.get(context).length).to eq(2)
    end
  end

  describe '#create' do
    it 'posts to the sendmail endpoint' do
      should = { name: 'mail-admin', type: 'sendmail', mailto: ['a@b.com'], ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/config/notifications/endpoints/sendmail')
        expect(body).to include('name' => 'mail-admin', 'mailto' => ['a@b.com'])
      end
      provider.create(context, 'mail-admin', should)
    end

    it 'posts to the smtp endpoint' do
      should = { name: 'relay', type: 'smtp', server: 'smtp.example.com',
                 from_address: 'pbs@example.com', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/config/notifications/endpoints/smtp')
        expect(body).to include('server' => 'smtp.example.com', 'from-address' => 'pbs@example.com')
      end
      provider.create(context, 'relay', should)
    end

    it 'posts to the gotify endpoint' do
      should = { name: 'gotify', type: 'gotify', server: 'https://gotify.example.com', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, _body|
        expect(path).to eq('/config/notifications/endpoints/gotify')
      end
      provider.create(context, 'gotify', should)
    end

    it 'posts to the webhook endpoint' do
      should = { name: 'wh', type: 'webhook', url: 'https://hooks.example.com',
                 http_method: 'post', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/config/notifications/endpoints/webhook')
        expect(body).to include('url' => 'https://hooks.example.com', 'method' => 'post')
      end
      provider.create(context, 'wh', should)
    end

    it 'excludes type and ensure from the POST body' do
      should = { name: 'mail-admin', type: 'sendmail', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('type')
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'mail-admin', should)
    end

    it 'includes smtp_password as password in the POST body' do
      should = { name: 'relay', type: 'smtp', smtp_password: 'secret', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('password' => 'secret')
      end
      provider.create(context, 'relay', should)
    end

    it 'unwraps a Sensitive smtp_password' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret')
      should = { name: 'relay', type: 'smtp', smtp_password: sensitive, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['password']).to eq('secret')
      end
      provider.create(context, 'relay', should)
    end

    it 'includes secret in the POST body for webhook' do
      secret = [{ 'name' => 'token', 'value' => 'aHVudGVyMg==' }]
      should = { name: 'wh', type: 'webhook', secret: secret, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('secret' => secret)
      end
      provider.create(context, 'wh', should)
    end

    it 'unwraps a Sensitive-wrapped secret' do
      secret = [{ 'name' => 'token', 'value' => 'aHVudGVyMg==' }]
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new(secret)
      should = { name: 'wh', type: 'webhook', secret: sensitive, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['secret']).to eq(secret)
      end
      provider.create(context, 'wh', should)
    end

    it 'includes token in the POST body for gotify' do
      should = { name: 'gotify', type: 'gotify', token: 'mytoken', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('token' => 'mytoken')
      end
      provider.create(context, 'gotify', should)
    end

    it 'excludes nil optional attributes from the POST body' do
      should = { name: 'mail-admin', type: 'sendmail', ensure: 'present',
                 comment: nil, author: nil, disable: nil }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('comment')
        expect(body).not_to have_key('author')
        expect(body).not_to have_key('disable')
      end
      provider.create(context, 'mail-admin', should)
    end
  end

  describe '#update' do
    it 'puts to the correct endpoint path' do
      should = { name: 'mail-admin', type: 'sendmail', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/config/notifications/endpoints/sendmail/mail-admin')
      end
      provider.update(context, 'mail-admin', should)
    end

    it 'excludes name and ensure from the PUT body' do
      should = { name: 'relay', type: 'smtp', server: 'smtp.example.com', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('name')
        expect(body).not_to have_key('ensure')
      end
      provider.update(context, 'relay', should)
    end

    it 'sends smtp_password on update when it differs from the stored one' do
      allow(store).to receive(:notification_secrets).with('smtp', 'relay', 'password').and_return(['stale'])
      should = { name: 'relay', type: 'smtp', smtp_password: 'newsecret', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('password' => 'newsecret')
      end
      provider.update(context, 'relay', should)
    end

    # The regression this mechanism exists to prevent: resending an unchanged
    # secret rewrote the stored value and minted a change event every run.
    it 'omits smtp_password when it already matches the stored one' do
      allow(store).to receive(:notification_secrets).with('smtp', 'relay', 'password').and_return(['newsecret'])
      should = { name: 'relay', type: 'smtp', smtp_password: 'newsecret', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('password')
      end
      provider.update(context, 'relay', should)
    end

    it 'omits the gotify token when it already matches the stored one' do
      allow(store).to receive(:notification_secrets).with('gotify', 'alerts', 'token').and_return(['tok'])
      should = { name: 'alerts', type: 'gotify', token: 'tok', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('token')
      end
      provider.update(context, 'alerts', should)
    end

    it 'rejects changing the cached target type' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/smtp', any_args)
                                            .and_return([{ 'name' => 'relay' }])
      provider.get(context)

      should = { name: 'relay', type: 'gotify', ensure: 'present' }
      expect { provider.update(context, 'relay', should) }
        .to raise_error(Puppet::ResourceError, %r{type cannot be changed from smtp to gotify})
    end
  end

  describe '#delete' do
    it 'sends DELETE to the correct endpoint using the cached type' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/endpoints/smtp', any_args)
                                            .and_return([{ 'name' => 'relay' }])
      provider.get(context)

      expect(mock_transport).to receive(:delete).with(context, '/config/notifications/endpoints/smtp/relay')
      provider.delete(context, 'relay')
    end

    it 'raises a clear error when the target type is unknown' do
      stub_all_empty
      provider.get(context)

      expect(mock_transport).not_to receive(:delete)
      expect { provider.delete(context, 'ghost') }
        .to raise_error(Puppet::ResourceError, %r{cannot delete notification target 'ghost'.*not found})
    end

    it 'raises a clear error when get was never called' do
      expect(mock_transport).not_to receive(:delete)
      expect { provider.delete(context, 'ghost') }
        .to raise_error(Puppet::ResourceError, %r{cannot delete notification target 'ghost'})
    end
  end
  # The webhook secret is the one secret that is neither a scalar nor stored
  # verbatim: PBS keeps it as a repeatable "name=<n>,value=<base64>" property
  # string, and the API returns names with the values stripped.
  describe 'webhook secret comparison' do
    let(:declared) { [{ 'name' => 'tok', 'value' => 'aHVudGVyMg==' }] }

    def stored(*entries)
      allow(store).to receive(:notification_secrets).with('webhook', 'hook', 'secret').and_return(entries)
    end

    def drifted?(secret = declared)
      provider.secret_drifted?(:secret, name: 'hook', type: 'webhook', secret: secret)
    end

    it 'matches an identical single entry' do
      stored('name=tok,value=aHVudGVyMg==')
      expect(drifted?).to be false
    end

    it 'reports drift when the base64 value differs' do
      stored('name=tok,value=b3RoZXI=')
      expect(drifted?).to be true
    end

    it 'reports drift when the name differs' do
      stored('name=other,value=aHVudGVyMg==')
      expect(drifted?).to be true
    end

    it 'ignores the order PBS renders entries in' do
      stored('name=b,value=Yg==', 'name=a,value=YQ==')
      expect(drifted?([{ 'name' => 'a', 'value' => 'YQ==' }, { 'name' => 'b', 'value' => 'Yg==' }])).to be false
    end

    it 'reports drift when PBS holds an extra secret' do
      stored('name=tok,value=aHVudGVyMg==', 'name=extra,value=ZQ==')
      expect(drifted?).to be true
    end

    # Base64 padding must survive the property-string split.
    it 'handles a padded base64 value' do
      stored('name=tok,value=U2VjdGVzdFdlYmhvb2tHR0dHNzc3Nw==')
      expect(drifted?([{ 'name' => 'tok', 'value' => 'U2VjdGVzdFdlYmhvb2tHR0dHNzc3Nw==' }])).to be false
    end

    # PBS expresses "keep the stored secret" as a name with no value.
    it 'treats a value-less declared entry as in sync' do
      stored('name=tok,value=aHVudGVyMg==')
      expect(drifted?([{ 'name' => 'tok' }])).to be false
    end

    it 'reports drift when PBS holds no secret at all' do
      allow(store).to receive(:notification_secrets).with('webhook', 'hook', 'secret').and_return([])
      expect(drifted?).to be true
    end
  end
end
