# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_notification_target'

RSpec.describe 'pbs_notification_target type' do
  let(:type) { Puppet::Type.type(:pbs_notification_target) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :name as the namevar' do
    expect(type.key_attributes).to include(:name)
  end

  describe 'name validation' do
    it 'accepts a safe-ID name' do
      expect { type.new(name: 'smtp_relay-01.prod', type: 'smtp') }.not_to raise_error
    end

    it 'rejects a name containing a slash' do
      expect { type.new(name: 'evil/../../name', type: 'smtp') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a name containing whitespace' do
      expect { type.new(name: 'bad name', type: 'smtp') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(name: 'mysmtp', type: 'smtp', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(name: 'mysmtp', type: 'smtp', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'type attribute' do
    ['sendmail', 'smtp', 'gotify', 'webhook'].each do |target_type|
      it "accepts #{target_type}" do
        expect { type.new(name: 'tgt', type: target_type) }.not_to raise_error
      end
    end

    it 'rejects an unknown type' do
      expect { type.new(name: 'tgt', type: 'slack') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'sendmail target' do
    subject(:resource) do
      type.new(
        name:         'sendmail-alerts',
        type:         'sendmail',
        author:       'PBS Alerts',
        from_address: 'pbs@example.com',
        mailto:       ['admin@example.com'],
        mailto_user:  ['root@pam'],
        comment:      'admin alerts',
        disable:      false,
      )
    end

    it { expect(resource[:name]).to eq('sendmail-alerts') }
    it { expect(resource[:type]).to eq('sendmail') }
    it { expect(resource[:author]).to eq('PBS Alerts') }
    it { expect(resource[:from_address]).to eq('pbs@example.com') }
    it { expect(resource[:mailto]).to eq(['admin@example.com']) }
    it { expect(resource[:mailto_user]).to eq(['root@pam']) }
    it { expect(resource[:comment]).to eq('admin alerts') }
    it { expect(resource[:disable]).to eq(:false) }
  end

  describe 'smtp target' do
    subject(:resource) do
      type.new(
        name:         'smtp-relay',
        type:         'smtp',
        server:       'smtp.example.com',
        port:         587,
        mode:         'starttls',
        username:     'pbs',
        from_address: 'pbs@example.com',
        mailto:       ['ops@example.com'],
      )
    end

    it { expect(resource[:server]).to eq('smtp.example.com') }
    it { expect(resource[:port]).to eq(587) }
    it { expect(resource[:mode]).to eq('starttls') }
    it { expect(resource[:username]).to eq('pbs') }
  end

  describe 'smtp_password parameter' do
    it 'accepts a plain string' do
      expect { type.new(name: 'smtp-relay', type: 'smtp', smtp_password: 'secret') }.not_to raise_error
    end

    it 'accepts a Sensitive value' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret')
      expect { type.new(name: 'smtp-relay', type: 'smtp', smtp_password: sensitive) }.not_to raise_error
    end
  end

  describe 'gotify target' do
    subject(:resource) do
      type.new(
        name:   'gotify-push',
        type:   'gotify',
        server: 'https://gotify.example.com',
      )
    end

    it { expect(resource[:server]).to eq('https://gotify.example.com') }
  end

  describe 'token parameter' do
    it 'accepts a plain string' do
      expect { type.new(name: 'gotify-push', type: 'gotify', token: 'mytoken') }.not_to raise_error
    end

    it 'accepts a Sensitive value' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('mytoken')
      expect { type.new(name: 'gotify-push', type: 'gotify', token: sensitive) }.not_to raise_error
    end
  end

  describe 'webhook target' do
    subject(:resource) do
      type.new(
        name:        'webhook-slack',
        type:        'webhook',
        url:         'https://hooks.example.com/notify',
        http_method: 'post',
        body:        '{"text": "{{message}}"}',
        header:      [{ 'name' => 'Content-Type', 'value' => 'application/json' }],
      )
    end

    it { expect(resource[:url]).to eq('https://hooks.example.com/notify') }
    it { expect(resource[:http_method]).to eq('post') }
    it { expect(resource[:body]).to eq('{"text": "{{message}}"}') }
    it { expect(resource[:header]).to eq([{ 'name' => 'Content-Type', 'value' => 'application/json' }]) }
  end

  describe 'secret parameter' do
    let(:secret_value) { [{ 'name' => 'token', 'value' => 'aHVudGVyMg==' }] }

    it 'accepts an array of hashes' do
      expect { type.new(name: 'wh', type: 'webhook', secret: secret_value) }.not_to raise_error
    end

    it 'accepts a Sensitive-wrapped array of hashes' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new(secret_value)
      expect { type.new(name: 'wh', type: 'webhook', secret: sensitive) }.not_to raise_error
    end

    it 'is marked sensitive so values are redacted from catalogs and logs' do
      expect(type.type_definition.attributes[:secret][:sensitive]).to be(true)
    end

    # A property, not a parameter: :parameter removed enforcement entirely,
    # so editing only the secret in Hiera changed nothing on the node.
    it 'is a property, so Puppet enforces it' do
      expect(type.attrtype(:secret)).to eq(:property)
    end
  end

  describe 'http_method attribute' do
    ['post', 'put', 'get'].each do |method|
      it "accepts #{method}" do
        expect { type.new(name: 'wh', type: 'webhook', http_method: method) }.not_to raise_error
      end
    end
  end

  describe 'mode attribute' do
    ['insecure', 'starttls', 'tls'].each do |m|
      it "accepts #{m}" do
        expect { type.new(name: 'smtp-relay', type: 'smtp', mode: m) }.not_to raise_error
      end
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(name: 'tgt', type: 'sendmail') }

    [:disable, :comment, :author, :from_address, :mailto, :mailto_user, :server, :port, :mode, :username, :url, :http_method, :body, :header].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end
end
