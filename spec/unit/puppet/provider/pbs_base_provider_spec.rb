# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'puppet/provider/pbs_base_provider'

class Puppet::Provider::TestProvider < Puppet::Provider::PbsBaseProvider
  def self.attribute_map
    {
      'name'        => :name,
      'gc-schedule' => :gc_schedule,
      'enabled'     => :enabled,
      'delete'      => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:enabled]
  end
end

class Puppet::Provider::PbsBootstrapTestProvider < Puppet::Provider::PbsBaseProvider
  attr_reader :updated

  def get(_context)
    [{ name: 'existing', ensure: 'present', enabled: false }]
  end

  def update(_context, name, should)
    @updated = [name, should]
  end
end

RSpec.describe Puppet::Provider::PbsBaseProvider do
  subject(:provider) { Puppet::Provider::TestProvider.new }

  let(:mock_type) { instance_double('Puppet::ResourceApi::Type') }
  let(:context)   { instance_double('Puppet::ResourceApi::BaseContext', type: mock_type) }

  describe '#pbs_to_puppet' do
    it 'maps PBS string keys to Puppet symbol keys' do
      result = provider.pbs_to_puppet('name' => 'mystore', 'gc-schedule' => 'daily')
      expect(result).to include(name: 'mystore', gc_schedule: 'daily')
    end

    it 'ignores keys not in attribute_map' do
      result = provider.pbs_to_puppet('name' => 'mystore', 'unknown-key' => 'value')
      expect(result).not_to have_key(:unknown_key)
      expect(result).not_to have_key('unknown-key')
    end

    it 'converts integer 1 to true for boolean attributes' do
      result = provider.pbs_to_puppet('enabled' => 1)
      expect(result[:enabled]).to be true
    end

    it 'converts integer 0 to false for boolean attributes' do
      result = provider.pbs_to_puppet('enabled' => 0)
      expect(result[:enabled]).to be false
    end

    it 'does not include keys absent from the input hash' do
      result = provider.pbs_to_puppet('name' => 'only-name')
      expect(result).not_to have_key(:gc_schedule)
      expect(result).not_to have_key(:enabled)
    end
  end

  describe '#puppet_to_pbs' do
    it 'maps Puppet symbol keys to PBS string keys' do
      result = provider.puppet_to_pbs(name: 'mystore', gc_schedule: 'daily')
      expect(result).to include('name' => 'mystore', 'gc-schedule' => 'daily')
    end

    it 'strips nil values' do
      result = provider.puppet_to_pbs(name: 'mystore', gc_schedule: nil)
      expect(result).not_to have_key('gc-schedule')
    end

    it 'keeps true as a boolean for PBS JSON bodies' do
      result = provider.puppet_to_pbs(enabled: true)
      expect(result['enabled']).to eq(true)
    end

    it 'converts Puppet :true symbols to boolean true for PBS JSON bodies' do
      result = provider.puppet_to_pbs(enabled: :true)
      expect(result['enabled']).to eq(true)
    end

    it 'keeps false as a boolean for PBS JSON bodies' do
      result = provider.puppet_to_pbs(enabled: false)
      expect(result['enabled']).to eq(false)
    end

    it 'converts Puppet :false symbols to boolean false for PBS JSON bodies' do
      result = provider.puppet_to_pbs(enabled: :false)
      expect(result['enabled']).to eq(false)
    end

    it 'unwraps a Sensitive value' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('s3cr3t')
      result = provider.puppet_to_pbs(name: sensitive)
      expect(result['name']).to eq('s3cr3t')
    end
  end

  describe '#request_body' do
    before(:each) { allow(mock_type).to receive(:namevars).and_return([:name]) }

    it 'drops :ensure from the body' do
      should = { name: 'mystore', gc_schedule: 'daily', ensure: 'present' }
      result = provider.request_body(context, should)
      expect(result).not_to have_key(:ensure)
      expect(result).not_to have_key('ensure')
    end

    it 'retains the namevar when for_update is false' do
      should = { name: 'mystore', ensure: 'present' }
      result = provider.request_body(context, should, for_update: false)
      expect(result).to include('name' => 'mystore')
    end

    it 'drops the namevar when for_update is true' do
      should = { name: 'mystore', gc_schedule: 'daily', ensure: 'present' }
      result = provider.request_body(context, should, for_update: true)
      expect(result).not_to have_key('name')
      expect(result).to include('gc-schedule' => 'daily')
    end

    it 'does not mutate the original should hash' do
      should = { name: 'mystore', ensure: 'present' }
      original = should.dup
      provider.request_body(context, should, for_update: true)
      expect(should).to eq(original)
    end

    it 'sends delete_properties as the PBS delete list on update' do
      should = { name: 'mystore', delete_properties: ['gc-schedule', 'enabled'], ensure: 'present' }
      result = provider.request_body(context, should, for_update: true)
      expect(result['delete']).to eq(['gc-schedule', 'enabled'])
    end

    it 'never sends a delete parameter on create even when delete_properties are declared' do
      should = { name: 'mystore', delete_properties: ['gc-schedule'], ensure: 'present' }
      result = provider.request_body(context, should)
      expect(result).not_to have_key('delete')
    end
  end

  describe '#insync? for delete_properties' do
    it 'requests deletion only while the targeted property still exists' do
      should = { delete_properties: ['gc-schedule'] }
      expect(provider.insync?(context, 'mystore', :delete_properties, { gc_schedule: 'daily' }, should)).to be(false)
      expect(provider.insync?(context, 'mystore', :delete_properties, {}, should)).to be(true)
    end

    it 'rejects deletion of properties the provider cannot observe' do
      expect {
        provider.insync?(context, 'mystore', :delete_properties, {}, delete_properties: ['unknown'])
      }.to raise_error(Puppet::ResourceError, %r{Cannot observe deleted PBS properties: unknown})
    end

    it 'falls back to the default comparison for ordinary properties' do
      expect(provider.insync?(context, 'mystore', :gc_schedule, { gc_schedule: 'a' }, gc_schedule: 'b')).to be_nil
    end
  end

  describe '.read_transport_config' do
    let(:config_dir) { Dir.mktmpdir('pbs-base-provider-spec') }
    let(:config_file) { File.join(config_dir, 'pbs_transport.yaml') }

    after(:each) do
      FileUtils.remove_entry(config_dir)
    end

    before(:each) do
      allow(Puppet::Provider::TestProvider).to receive(:config_path).and_return(config_file)
    end

    it 'raises TransportConfigMissing when the file does not exist' do
      expect { Puppet::Provider::TestProvider.read_transport_config }
        .to raise_error(described_class::TransportConfigMissing, %r{not found at})
    end

    it 'raises TransportConfigMissing when the file is empty (YAML.safe_load_file returns nil)' do
      File.write(config_file, '')
      expect { Puppet::Provider::TestProvider.read_transport_config }
        .to raise_error(described_class::TransportConfigMissing, %r{empty or not a YAML mapping})
    end

    it 'raises TransportConfigMissing when the file is not a YAML mapping' do
      File.write(config_file, "- just\n- a\n- list\n")
      expect { Puppet::Provider::TestProvider.read_transport_config }
        .to raise_error(described_class::TransportConfigMissing, %r{empty or not a YAML mapping})
    end

    it 'returns the config with symbolized keys' do
      File.write(config_file, "host: pbs.example.com\ntoken_id: user@pbs!t\ntoken_secret: s3cret\n")
      expect(Puppet::Provider::TestProvider.read_transport_config)
        .to eq(host: 'pbs.example.com', token_id: 'user@pbs!t', token_secret: 's3cret')
    end

    it 'raises an exception that is also a Puppet::ResourceError' do
      expect { Puppet::Provider::TestProvider.read_transport_config }
        .to raise_error(Puppet::ResourceError)
    end
  end

  describe 'transport bootstrap' do
    it 'treats a missing managed transport config as empty during discovery' do
      allow(provider).to receive(:pbs_transport)
        .and_raise(described_class::TransportConfigMissing,
                   'PBS transport config not found at /tmp/pbs_transport.yaml; apply class')

      expect(provider.transport_get(context, '/config/datastore')).to eq([])
    end

    it 'detects the missing config by exception class, not by message text' do
      allow(provider).to receive(:pbs_transport)
        .and_raise(described_class::TransportConfigMissing, 'some completely different wording')

      expect(provider.transport_get(context, '/config/datastore')).to eq([])
    end

    it 'propagates other resource errors unchanged' do
      allow(provider).to receive(:pbs_transport)
        .and_raise(Puppet::ResourceError, 'PBS API error 500 on /config/datastore: boom')

      expect { provider.transport_get(context, '/config/datastore') }
        .to raise_error(Puppet::ResourceError, %r{500})
    end

    it 'passes path and query through to the transport' do
      transport = instance_double('Puppet::Transport::ProxmoxBackupServer')
      allow(provider).to receive(:pbs_transport).and_return(transport)
      expect(transport).to receive(:get).with(context, '/access/acl', { 'exact' => 1 }).and_return([])

      provider.transport_get(context, '/access/acl', 'exact' => 1)
    end

    it 'passes a nil query through to the transport' do
      transport = instance_double('Puppet::Transport::ProxmoxBackupServer')
      allow(provider).to receive(:pbs_transport).and_return(transport)
      expect(transport).to receive(:get).with(context, '/config/datastore', nil).and_return([])

      provider.transport_get(context, '/config/datastore')
    end

    it 'refreshes actual state before applying changes after first-run bootstrap' do
      bootstrap_provider = Puppet::Provider::PbsBootstrapTestProvider.new
      bootstrap_provider.instance_variable_set(:@transport_config_missing, true)
      bootstrap_type = instance_double(
        'Puppet::ResourceApi::Type',
        namevars: [:name],
        ensurable?: true,
        feature?: false,
        attributes: {},
      )
      bootstrap_context = instance_double('Puppet::ResourceApi::BaseContext', type: bootstrap_type)
      allow(bootstrap_context).to receive(:updating).and_yield
      allow(bootstrap_context).to receive(:creating).and_yield
      allow(bootstrap_context).to receive(:deleting).and_yield
      allow(bootstrap_type).to receive(:check_schema)

      bootstrap_provider.set(
        bootstrap_context,
        'existing' => { should: { name: 'existing', ensure: 'present', enabled: true } },
      )

      expect(bootstrap_provider.updated).to eq(['existing', { name: 'existing', ensure: 'present', enabled: true }])
    end
  end
end
