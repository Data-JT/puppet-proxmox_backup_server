# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_realm'

RSpec.describe 'pbs_realm type' do
  let(:type) { Puppet::Type.type(:pbs_realm) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :realm as the namevar' do
    expect(type.key_attributes).to include(:realm)
  end

  describe 'realm name validation' do
    it 'accepts a safe-ID realm name' do
      expect { type.new(realm: 'corp-ldap.01_x', type: 'ldap') }.not_to raise_error
    end

    it 'rejects a realm name containing a slash' do
      expect { type.new(realm: '../etc/passwd', type: 'ldap') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a realm name containing whitespace' do
      expect { type.new(realm: 'bad realm', type: 'ldap') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(realm: 'myldap', type: 'ldap', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(realm: 'myldap', type: 'ldap', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'type attribute' do
    ['ldap', 'ad', 'openid'].each do |realm_type|
      it "accepts #{realm_type}" do
        expect { type.new(realm: 'r', type: realm_type) }.not_to raise_error
      end
    end

    it 'rejects an unknown type' do
      expect { type.new(realm: 'r', type: 'radius') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'LDAP realm' do
    subject(:resource) do
      type.new(
        realm:    'corp-ldap',
        type:     'ldap',
        server1:  'ldap.example.com',
        base_dn:  'dc=example,dc=com',
        user_attr: 'uid',
        bind_dn:  'cn=search,dc=example,dc=com',
        port:     389,
        mode:     'ldap+starttls',
        verify:   true,
        comment:  'Corporate LDAP',
      )
    end

    it { expect(resource[:realm]).to eq('corp-ldap') }
    it { expect(resource[:type]).to eq('ldap') }
    it { expect(resource[:server1]).to eq('ldap.example.com') }
    it { expect(resource[:base_dn]).to eq('dc=example,dc=com') }
    it { expect(resource[:user_attr]).to eq('uid') }
    it { expect(resource[:bind_dn]).to eq('cn=search,dc=example,dc=com') }
    it { expect(resource[:port]).to eq(389) }
    it { expect(resource[:mode]).to eq('ldap+starttls') }
    it { expect(resource[:comment]).to eq('Corporate LDAP') }
  end

  describe 'mode attribute' do
    ['ldap', 'ldap+starttls', 'ldaps'].each do |m|
      it "accepts #{m}" do
        expect { type.new(realm: 'r', type: 'ldap', mode: m) }.not_to raise_error
      end
    end

    it 'rejects an unknown mode' do
      expect { type.new(realm: 'r', type: 'ldap', mode: 'plain') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'bind_password parameter' do
    it 'accepts a plain string' do
      expect { type.new(realm: 'r', type: 'ldap', bind_password: 'secret') }.not_to raise_error
    end

    it 'accepts a Sensitive value' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret')
      expect { type.new(realm: 'r', type: 'ldap', bind_password: sensitive) }.not_to raise_error
    end
  end

  describe 'AD realm' do
    subject(:resource) do
      type.new(
        realm:   'corp-ad',
        type:    'ad',
        server1: 'ad.example.com',
        base_dn: 'dc=example,dc=com',
        mode:    'ldaps',
      )
    end

    it { expect(resource[:type]).to eq('ad') }
    it { expect(resource[:server1]).to eq('ad.example.com') }
    it { expect(resource[:mode]).to eq('ldaps') }
  end

  describe 'OpenID realm' do
    subject(:resource) do
      type.new(
        realm:          'sso',
        type:           'openid',
        issuer_url:     'https://sso.example.com',
        client_id:      'proxmox-backup',
        username_claim: 'email',
        autocreate:     true,
        scopes:         'openid email profile',
        comment:        'Corporate SSO',
      )
    end

    it { expect(resource[:type]).to eq('openid') }
    it { expect(resource[:issuer_url]).to eq('https://sso.example.com') }
    it { expect(resource[:client_id]).to eq('proxmox-backup') }
    it { expect(resource[:username_claim]).to eq('email') }
    it { expect(resource[:scopes]).to eq('openid email profile') }
    it { expect(resource[:comment]).to eq('Corporate SSO') }
  end

  describe 'client_key parameter' do
    it 'accepts a plain string' do
      expect { type.new(realm: 'sso', type: 'openid', client_key: 'mysecret') }.not_to raise_error
    end

    it 'accepts a Sensitive value' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('mysecret')
      expect { type.new(realm: 'sso', type: 'openid', client_key: sensitive) }.not_to raise_error
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(realm: 'r', type: 'ldap') }

    [:comment, :default, :server1, :server2, :port, :bind_dn, :mode, :verify, :capath, :filter, :sync_defaults_options, :sync_attributes, :user_classes, :base_dn, :user_attr, :issuer_url, :client_id,
     :username_claim, :autocreate, :scopes, :prompt, :acr_values, :audiences].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end
end
