# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_realm/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsRealm::ProxmoxBackupServer do
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
    allow(mock_type).to receive(:namevars).and_return([:realm])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
  end

  def stub_all_empty
    ['ldap', 'ad', 'openid'].each do |t|
      allow(mock_transport).to receive(:get).with(context, "/config/access/#{t}", any_args).and_return([])
    end
  end

  describe '#get' do
    it 'returns [] when all endpoints return nil' do
      ['ldap', 'ad', 'openid'].each do |t|
        allow(mock_transport).to receive(:get).with(context, "/config/access/#{t}", any_args).and_return(nil)
      end
      expect(provider.get(context)).to eq([])
    end

    it 'queries all three realm type endpoints' do
      ['ldap', 'ad', 'openid'].each do |t|
        expect(mock_transport).to receive(:get).with(context, "/config/access/#{t}", any_args).and_return([])
      end
      provider.get(context)
    end

    it 'maps an LDAP realm to a Puppet resource hash' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/access/ldap', any_args)
                                            .and_return([{
                                                          'realm' => 'corp-ldap',
          'server1'  => 'ldap.example.com',
          'base-dn'  => 'dc=example,dc=com',
          'user-attr' => 'uid',
          'comment' => 'Corporate LDAP',
                                                        }])

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          realm:     'corp-ldap',
          type:      'ldap',
          server1:   'ldap.example.com',
          base_dn:   'dc=example,dc=com',
          user_attr: 'uid',
          comment:   'Corporate LDAP',
          ensure:    'present',
        ),
      )
    end

    it 'maps an AD realm' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/access/ad', any_args)
                                            .and_return([{ 'realm' => 'corp-ad', 'server1' => 'ad.example.com', 'mode' => 'ldaps' }])

      result = provider.get(context)
      expect(result.first).to include(realm: 'corp-ad', type: 'ad', server1: 'ad.example.com', mode: 'ldaps')
    end

    it 'maps an OpenID realm' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/access/openid', any_args)
                                            .and_return([{
                                                          'realm' => 'sso',
          'issuer-url'     => 'https://sso.example.com',
          'client-id'      => 'proxmox-backup',
          'username-claim' => 'email',
                                                        }])

      result = provider.get(context)
      expect(result.first).to include(
        realm:          'sso',
        type:           'openid',
        issuer_url:     'https://sso.example.com',
        client_id:      'proxmox-backup',
        username_claim: 'email',
      )
    end

    it 'converts verify boolean true' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/access/ldap', any_args)
                                            .and_return([{ 'realm' => 'r', 'verify' => true }])
      expect(provider.get(context).first[:verify]).to be(true)
    end

    it 'converts default boolean false' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/access/ldap', any_args)
                                            .and_return([{ 'realm' => 'r', 'default' => false }])
      expect(provider.get(context).first[:default]).to be(false)
    end

    it 'translates bind-dn to bind_dn' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/access/ldap', any_args)
                                            .and_return([{ 'realm' => 'r', 'bind-dn' => 'cn=search,dc=example,dc=com' }])
      expect(provider.get(context).first[:bind_dn]).to eq('cn=search,dc=example,dc=com')
    end

    it 'translates sync-defaults-options to sync_defaults_options' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/access/ldap', any_args)
                                            .and_return([{ 'realm' => 'r', 'sync-defaults-options' => 'scope=subtree' }])
      expect(provider.get(context).first[:sync_defaults_options]).to eq('scope=subtree')
    end

    it 'populates the internal type cache for use by delete' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/access/openid', any_args)
                                            .and_return([{ 'realm' => 'sso', 'issuer-url' => 'https://sso.example.com', 'client-id' => 'pbs' }])
      provider.get(context)

      expect(mock_transport).to receive(:delete).with(context, '/config/access/openid/sso')
      provider.delete(context, 'sso')
    end

    it 'merges results from multiple realm types' do
      allow(mock_transport).to receive(:get).with(context, '/config/access/ldap', any_args)
                                            .and_return([{ 'realm' => 'corp-ldap' }])
      allow(mock_transport).to receive(:get).with(context, '/config/access/ad', any_args)
                                            .and_return([{ 'realm' => 'corp-ad' }])
      allow(mock_transport).to receive(:get).with(context, '/config/access/openid', any_args)
                                            .and_return([])

      expect(provider.get(context).length).to eq(2)
    end
  end

  describe '#create' do
    it 'posts to /config/access/ldap for an LDAP realm' do
      should = {
        realm: 'corp-ldap', type: 'ldap', server1: 'ldap.example.com',
        base_dn: 'dc=example,dc=com', user_attr: 'uid', ensure: 'present',
      }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/config/access/ldap')
        expect(body).to include(
          'realm'     => 'corp-ldap',
          'server1'   => 'ldap.example.com',
          'base-dn'   => 'dc=example,dc=com',
          'user-attr' => 'uid',
        )
      end
      provider.create(context, 'corp-ldap', should)
    end

    it 'posts to /config/access/ad for an AD realm' do
      should = { realm: 'corp-ad', type: 'ad', server1: 'ad.example.com', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, _body|
        expect(path).to eq('/config/access/ad')
      end
      provider.create(context, 'corp-ad', should)
    end

    it 'posts to /config/access/openid for an OpenID realm' do
      should = {
        realm: 'sso', type: 'openid', issuer_url: 'https://sso.example.com',
        client_id: 'pbs', ensure: 'present',
      }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/config/access/openid')
        expect(body).to include('issuer-url' => 'https://sso.example.com', 'client-id' => 'pbs')
      end
      provider.create(context, 'sso', should)
    end

    it 'excludes type and ensure from the POST body' do
      should = { realm: 'r', type: 'ldap', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('type')
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'r', should)
    end

    it 'includes bind_password as password in the POST body' do
      should = { realm: 'r', type: 'ldap', bind_password: 'secret', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('password' => 'secret')
      end
      provider.create(context, 'r', should)
    end

    it 'unwraps a Sensitive bind_password' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret')
      should = { realm: 'r', type: 'ldap', bind_password: sensitive, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['password']).to eq('secret')
      end
      provider.create(context, 'r', should)
    end

    it 'includes client_key for OpenID' do
      should = { realm: 'sso', type: 'openid', client_key: 'mysecret', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('client-key' => 'mysecret')
      end
      provider.create(context, 'sso', should)
    end

    it 'excludes nil optional attributes from the POST body' do
      should = { realm: 'r', type: 'ldap', server2: nil, comment: nil, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('server2')
        expect(body).not_to have_key('comment')
      end
      provider.create(context, 'r', should)
    end
  end

  describe '#update' do
    it 'puts to /config/access/{type}/{realm}' do
      should = { realm: 'corp-ldap', type: 'ldap', comment: 'updated', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/config/access/ldap/corp-ldap')
      end
      provider.update(context, 'corp-ldap', should)
    end

    it 'excludes realm and ensure from the PUT body' do
      should = { realm: 'corp-ldap', type: 'ldap', comment: 'updated', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('realm')
        expect(body).not_to have_key('ensure')
        expect(body).to include('comment' => 'updated')
      end
      provider.update(context, 'corp-ldap', should)
    end

    it 'uses bind-dn (hyphenated) in PUT body' do
      should = { realm: 'r', type: 'ldap', bind_dn: 'cn=s,dc=x,dc=com', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('bind-dn' => 'cn=s,dc=x,dc=com')
        expect(body).not_to have_key('bind_dn')
      end
      provider.update(context, 'r', should)
    end

    it 'rejects changing the cached realm type' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/access/ldap', any_args)
                                            .and_return([{ 'realm' => 'corp' }])
      provider.get(context)

      should = { realm: 'corp', type: 'ad', ensure: 'present' }
      expect { provider.update(context, 'corp', should) }
        .to raise_error(Puppet::ResourceError, %r{type cannot be changed from ldap to ad})
    end
  end

  describe '#delete' do
    it 'sends DELETE to the correct endpoint using the cached type' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/config/access/ldap', any_args)
                                            .and_return([{ 'realm' => 'corp-ldap' }])
      provider.get(context)

      expect(mock_transport).to receive(:delete).with(context, '/config/access/ldap/corp-ldap')
      provider.delete(context, 'corp-ldap')
    end

    it 'raises a clear error when the realm type is unknown' do
      stub_all_empty
      provider.get(context)

      expect(mock_transport).not_to receive(:delete)
      expect { provider.delete(context, 'ghost') }
        .to raise_error(Puppet::ResourceError, %r{cannot delete realm 'ghost'.*not found})
    end

    it 'raises a clear error when get was never called' do
      expect(mock_transport).not_to receive(:delete)
      expect { provider.delete(context, 'ghost') }
        .to raise_error(Puppet::ResourceError, %r{cannot delete realm 'ghost'})
    end
  end
end
