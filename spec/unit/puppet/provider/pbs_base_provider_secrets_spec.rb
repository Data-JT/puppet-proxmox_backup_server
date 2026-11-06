# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'

# Minimal provider exercising the base class's secret dispatch in isolation,
# so the contract is pinned independently of any one PBS resource type.
class Puppet::Provider::PbsSecretTestProvider < Puppet::Provider::PbsBaseProvider
  attr_accessor :stored

  def self.attribute_map
    { 'name' => :name, 'comment' => :comment, 'password' => :password }
  end

  def self.secret_attributes
    [:password]
  end

  def stored_secret(_attribute_name, _should)
    @stored
  end
end

RSpec.describe Puppet::Provider::PbsBaseProvider do
  subject(:provider) { Puppet::Provider::PbsSecretTestProvider.new }

  let(:store) { PuppetX::ProxmoxBackupServer::SecretStore }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:name]) }
  let(:should_hash) { { name: 'thing', password: 'hunter2', comment: 'c' } }

  before(:each) { allow(store).to receive(:assert_available!) }

  describe '#insync?' do
    it 'returns nil for an attribute it does not own, so Puppet compares normally' do
      expect(provider.insync?(context, 'thing', :comment, {}, should_hash)).to be_nil
    end

    it 'reports in sync when the stored secret matches' do
      provider.stored = 'hunter2'
      expect(provider.insync?(context, 'thing', :password, {}, should_hash)).to be true
    end

    it 'reports drift when the stored secret differs' do
      provider.stored = 'different'
      expect(provider.insync?(context, 'thing', :password, {}, should_hash)).to eq([false, 'password changed'])
    end

    it 'reports drift when PBS holds no secret at all' do
      provider.stored = nil
      expect(provider.insync?(context, 'thing', :password, {}, should_hash)).to eq([false, 'password changed'])
    end

    # An undeclared secret is not managed, so whatever PBS holds is correct.
    it 'reports in sync when the secret is not declared' do
      provider.stored = 'anything'
      expect(provider.insync?(context, 'thing', :password, {}, name: 'thing')).to be true
    end

    it 'unwraps a Sensitive-wrapped declared value before comparing' do
      provider.stored = 'hunter2'
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('hunter2')
      expect(provider.insync?(context, 'thing', :password, {}, name: 'thing', password: sensitive)).to be true
    end

    # Fail closed: never report a match for a value that cannot be seen.
    it 'raises when the store is unreadable' do
      allow(store).to receive(:assert_available!).and_raise(Puppet::ResourceError, 'not readable')
      expect { provider.insync?(context, 'thing', :password, {}, should_hash) }
        .to raise_error(Puppet::ResourceError, 'not readable')
    end

    it 'does not consult the store for an attribute it does not own' do
      expect(store).not_to receive(:assert_available!)
      provider.insync?(context, 'thing', :comment, {}, should_hash)
    end
  end

  describe '#update_body' do
    # The regression this whole mechanism exists to prevent: an unchanged
    # secret must not be resent, because PBS keeps what a PUT omits.
    it 'omits a secret that is already in sync' do
      provider.stored = 'hunter2'
      expect(provider.update_body(context, should_hash)).to eq('comment' => 'c')
    end

    it 'includes a secret that has drifted' do
      provider.stored = 'stale'
      expect(provider.update_body(context, should_hash)).to eq('comment' => 'c', 'password' => 'hunter2')
    end

    it 'includes a secret PBS does not hold yet' do
      provider.stored = nil
      expect(provider.update_body(context, should_hash)).to eq('comment' => 'c', 'password' => 'hunter2')
    end

    it 'strips the namevar as request_body does' do
      provider.stored = 'hunter2'
      expect(provider.update_body(context, should_hash)).not_to include('name')
    end
  end

  # Load-bearing, and easy to lose in a later edit: without the feature flag
  # Resource API never defines the custom insync? singleton method
  # (resource_api/property.rb:28) and every secret silently falls back to the
  # default comparison, which is the bug this mechanism removes.
  describe 'custom_insync feature declaration' do
    [:pbs_realm, :pbs_remote, :pbs_s3_endpoint, :pbs_notification_target, :pbs_user].each do |type_name|
      it "#{type_name} declares custom_insync" do
        require "puppet/type/#{type_name}"
        expect(Puppet::Type.type(type_name).type_definition.feature?('custom_insync')).to be true
      end
    end
  end

  describe '#stored_secret' do
    it 'raises when a provider declares secrets without implementing it' do
      incomplete = Class.new(Puppet::Provider::PbsBaseProvider) do
        def self.secret_attributes
          [:password]
        end
      end
      expect { incomplete.new.stored_secret(:password, {}) }.to raise_error(NotImplementedError)
    end
  end
end
