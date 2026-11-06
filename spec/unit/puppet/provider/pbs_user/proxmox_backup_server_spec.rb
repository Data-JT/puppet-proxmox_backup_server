# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_user/proxmox_backup_server'
require 'fiddle'
require 'tmpdir'

RSpec.describe Puppet::Provider::PbsUser::ProxmoxBackupServer do
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
    # No example touches a real /etc/proxmox-backup; shadow.json is stubbed or
    # redirected to a tmpdir.
    allow(store).to receive_messages(available?: true, user_password_hash: nil)
    allow(provider).to receive(:pbs_transport).and_return(mock_transport)
    allow(mock_type).to receive(:namevars).and_return([:userid])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
  end

  describe '#get' do
    it 'returns [] when the API returns nil' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the API returns an empty array' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args).and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'maps the API response to Puppet resource hashes' do
      api_data = [
        {
          'userid'    => 'john@pbs',
          'comment'   => 'John Doe',
          'email'     => 'john@example.com',
          'enable'    => 1,
          'firstname' => 'John',
          'lastname'  => 'Doe',
        },
      ]
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          userid:    'john@pbs',
          comment:   'John Doe',
          email:     'john@example.com',
          enable:    true,
          firstname: 'John',
          lastname:  'Doe',
          ensure:    'present',
        ),
      )
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end

    # shadow.json only backs the built-in @pbs realm; other realms authenticate
    # elsewhere and must never appear to have a managed password.
    it 'reports a password placeholder only for @pbs realm users' do
      api_data = [
        { 'userid' => 'john@pbs' },
        { 'userid' => 'john@pam' },
        { 'userid' => 'john@ldap' },
      ]
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args).and_return(api_data)
      allow(store).to receive(:user_password_hash).with('john@pbs').and_return('$y$stored-hash')

      result = provider.get(context)

      pbs_user  = result.find { |u| u[:userid] == 'john@pbs' }
      pam_user  = result.find { |u| u[:userid] == 'john@pam' }
      ldap_user = result.find { |u| u[:userid] == 'john@ldap' }
      expect(pbs_user[:password]).to eq('[secret managed]')
      expect(pam_user).not_to have_key(:password)
      expect(ldap_user).not_to have_key(:password)
    end

    # A constant, because a placeholder that varied between runs would itself
    # be reported as drift.
    it 'never reports the stored hash as the is value' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'john@pbs' }])
      allow(store).to receive(:user_password_hash).and_return('$y$stored-hash')
      expect(provider.get(context).first[:password]).not_to include('stored-hash')
    end

    it 'omits password entirely when PBS holds none' do
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                            .and_return([{ 'userid' => 'john@pbs' }])
      allow(store).to receive(:user_password_hash).and_return(nil)
      expect(provider.get(context).first).not_to have_key(:password)
    end
  end

  describe 'enable boolean round-trip' do
    it 'converts API integer 1 to Puppet true' do
      api_data = [{ 'userid' => 'user@pbs', 'enable' => 1 }]
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result.first[:enable]).to be(true)
    end

    it 'converts API integer 0 to Puppet false' do
      api_data = [{ 'userid' => 'user@pbs', 'enable' => 0 }]
      allow(mock_transport).to receive(:get).with(context, '/access/users', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result.first[:enable]).to be(false)
    end

    it 'sends Puppet :true as a boolean in POST body' do
      should = { userid: 'user@pbs', enable: :true, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['enable']).to eq(true)
      end
      provider.create(context, 'user@pbs', should)
    end

    it 'sends Puppet :false as a boolean in POST body' do
      should = { userid: 'user@pbs', enable: :false, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['enable']).to eq(false)
      end
      provider.create(context, 'user@pbs', should)
    end
  end

  describe 'userid format validation' do
    it 'raises on create when userid has no realm' do
      should = { userid: 'useronly', enable: true, ensure: 'present' }
      expect { provider.create(context, 'useronly', should) }
        .to raise_error(Puppet::ResourceError, %r{userid must be in user@realm format})
    end

    it 'raises on create when userid has multiple @ signs' do
      should = { userid: 'user@realm@extra', enable: true, ensure: 'present' }
      expect { provider.create(context, 'user@realm@extra', should) }
        .to raise_error(Puppet::ResourceError, %r{userid must be in user@realm format})
    end

    it 'raises on update when userid has no realm' do
      should = { userid: 'useronly', enable: true, ensure: 'present' }
      expect { provider.update(context, 'useronly', should) }
        .to raise_error(Puppet::ResourceError, %r{userid must be in user@realm format})
    end

    it 'does not raise on create for a valid userid' do
      should = { userid: 'john@pbs', enable: true, ensure: 'present' }
      allow(mock_transport).to receive(:post)
      expect { provider.create(context, 'john@pbs', should) }.not_to raise_error
    end
  end

  describe 'password realm validation' do
    it 'raises on create when a password is set for a non-@pbs realm user' do
      should = { userid: 'svc@pam', enable: true, ensure: 'present', password: 'secret' }
      expect(mock_transport).not_to receive(:post)
      expect { provider.create(context, 'svc@pam', should) }
        .to raise_error(Puppet::ResourceError, %r{password management is only supported for @pbs realm users})
    end

    it 'raises on update when a password is set for a non-@pbs realm user' do
      should = { userid: 'svc@ldap', enable: true, ensure: 'present', password: 'secret' }
      allow(mock_transport).to receive(:put)
      expect { provider.update(context, 'svc@ldap', should) }
        .to raise_error(Puppet::ResourceError, %r{password management is only supported for @pbs realm users})
    end

    it 'does not raise on create for a non-@pbs realm user without a password' do
      should = { userid: 'svc@pam', enable: true, ensure: 'present' }
      allow(mock_transport).to receive(:post)
      expect { provider.create(context, 'svc@pam', should) }.not_to raise_error
    end
  end

  describe '#create' do
    it 'posts to /access/users with userid' do
      should = { userid: 'john@pbs', enable: true, ensure: 'present', comment: nil }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/access/users')
        expect(body).to include('userid' => 'john@pbs')
      end
      provider.create(context, 'john@pbs', should)
    end

    it 'excludes ensure from the POST body' do
      should = { userid: 'john@pbs', enable: true, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'john@pbs', should)
    end

    it 'excludes nil attributes from the POST body' do
      should = { userid: 'john@pbs', enable: true, ensure: 'present', comment: nil, email: nil }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('comment')
        expect(body).not_to have_key('email')
      end
      provider.create(context, 'john@pbs', should)
    end

    it 'includes password in the POST body when provided' do
      should = { userid: 'john@pbs', enable: true, ensure: 'present', password: 'hunter2' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('password' => 'hunter2')
      end
      provider.create(context, 'john@pbs', should)
    end

    it 'unwraps Sensitive password before sending' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('hunter2')
      should = { userid: 'john@pbs', enable: true, ensure: 'present', password: sensitive }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['password']).to eq('hunter2')
      end
      provider.create(context, 'john@pbs', should)
    end

    it 'omits password key when password is not provided' do
      should = { userid: 'john@pbs', enable: true, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('password')
      end
      provider.create(context, 'john@pbs', should)
    end
  end

  describe '#update' do
    it 'puts to /access/users/{userid}' do
      should = { userid: 'john@pbs', enable: true, ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/access/users/john@pbs')
      end
      provider.update(context, 'john@pbs', should)
    end

    it 'excludes userid, ensure, and nil values from the PUT body' do
      should = {
        userid:   'john@pbs',
        enable:   :true,
        ensure:   'present',
        comment:  nil,
        email:    'john@example.com',
      }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('email' => 'john@example.com', 'enable' => true)
        expect(body).not_to have_key('userid')
        expect(body).not_to have_key('ensure')
        expect(body).not_to have_key('comment')
      end
      provider.update(context, 'john@pbs', should)
    end
  end

  # password_login => false is how a token-only user is kept from logging in:
  # PBS has no API to remove a password, so the shadow.json entry is removed.
  describe 'password_login' do
    let(:writer) { PuppetX::ProxmoxBackupServer::ShadowWriter }

    before(:each) do
      allow(mock_transport).to receive(:put)
      allow(mock_transport).to receive(:post)
    end

    describe '#get' do
      it 'reports true for a @pbs user with a stored hash' do
        allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                              .and_return([{ 'userid' => 'john@pbs' }])
        allow(store).to receive(:user_password_hash).with('john@pbs').and_return('$y$stored-hash')
        expect(provider.get(context).first[:password_login]).to be true
      end

      it 'reports false for a @pbs user without a stored hash' do
        allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                              .and_return([{ 'userid' => 'john@pbs' }])
        expect(provider.get(context).first[:password_login]).to be false
      end

      it 'omits it for users outside the @pbs realm' do
        allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                              .and_return([{ 'userid' => 'john@pam' }])
        expect(provider.get(context).first).not_to have_key(:password_login)
      end

      # get() runs for every resource, also off a PBS node; it must not raise.
      it 'omits it when shadow.json cannot be read' do
        allow(store).to receive(:available?).and_return(false)
        allow(mock_transport).to receive(:get).with(context, '/access/users', any_args)
                                              .and_return([{ 'userid' => 'john@pbs' }])
        expect(provider.get(context).first).not_to have_key(:password_login)
      end
    end

    describe '#update' do
      it 'removes the stored hash when false' do
        expect(writer).to receive(:remove_password).with('john@pbs')
        provider.update(context, 'john@pbs', userid: 'john@pbs', ensure: 'present', password_login: false)
      end

      it 'never sends password_login to the API' do
        allow(writer).to receive(:remove_password)
        expect(mock_transport).to receive(:put) do |_ctx, _path, body|
          expect(body).not_to have_key('password_login')
        end
        provider.update(context, 'john@pbs', userid: 'john@pbs', ensure: 'present', password_login: false)
      end

      it 'leaves shadow.json alone when not declared' do
        expect(writer).not_to receive(:remove_password)
        provider.update(context, 'john@pbs', userid: 'john@pbs', ensure: 'present')
      end

      it 'raises before any change when combined with a password' do
        expect(mock_transport).not_to receive(:put)
        expect(writer).not_to receive(:remove_password)
        expect {
          provider.update(context, 'john@pbs', userid: 'john@pbs', ensure: 'present', password_login: false, password: 'x')
        }.to raise_error(Puppet::ResourceError, %r{password_login => false contradicts a declared password})
      end

      # Nothing can create a login without a value, so true needs a password.
      it 'raises when true without a password and none is stored' do
        expect {
          provider.update(context, 'john@pbs', userid: 'john@pbs', ensure: 'present', password_login: true)
        }.to raise_error(Puppet::ResourceError, %r{password_login => true requires a password})
      end

      it 'raises for users outside the @pbs realm' do
        expect(mock_transport).not_to receive(:put)
        expect {
          provider.update(context, 'svc@pam', userid: 'svc@pam', ensure: 'present', password_login: false)
        }.to raise_error(Puppet::ResourceError, %r{password management is only supported for @pbs realm users})
      end
    end

    describe '#create' do
      it 'raises before posting when combined with a password' do
        expect(mock_transport).not_to receive(:post)
        expect {
          provider.create(context, 'john@pbs', userid: 'john@pbs', ensure: 'present', password_login: false, password: 'x')
        }.to raise_error(Puppet::ResourceError, %r{contradicts a declared password})
      end

      # A user created without a password has no shadow.json entry at all.
      it 'creates the user without a password when false' do
        expect(mock_transport).to receive(:post) do |_ctx, _path, body|
          expect(body).not_to have_key('password')
          expect(body).not_to have_key('password_login')
        end
        provider.create(context, 'john@pbs', userid: 'john@pbs', ensure: 'present', password_login: false)
      end
    end
  end

  describe '#delete' do
    it 'sends DELETE to /access/users/{userid}' do
      expect(mock_transport).to receive(:delete).with(context, '/access/users/john@pbs')
      provider.delete(context, 'john@pbs')
    end
  end
end
