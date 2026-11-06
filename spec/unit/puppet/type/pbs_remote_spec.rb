# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_remote'

RSpec.describe 'pbs_remote type' do
  let(:type) { Puppet::Type.type(:pbs_remote) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :name as the namevar' do
    expect(type.key_attributes).to include(:name)
  end

  describe 'name namevar validation' do
    it 'accepts a PBS safe-ID' do
      expect { type.new(name: 'offsite_pbs-1.a') }.not_to raise_error
    end

    it 'rejects a name with a slash (URL path injection)' do
      expect { type.new(name: 'bad/../remote') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a name with whitespace' do
      expect { type.new(name: 'bad remote') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(name: 'myremote', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(name: 'myremote', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'password attribute' do
    # A property, not a parameter: :parameter removed enforcement entirely,
    # so editing only the password in Hiera changed nothing on the node.
    it 'is a property, so Puppet enforces it' do
      expect(type.attrtype(:password)).to eq(:property)
    end

    it 'is marked sensitive in the type definition' do
      # Wrapping into Puppet::Pops::Types::PSensitiveType::Sensitive only
      # happens during catalog compilation (when initialised from a
      # Puppet::Resource).  In unit tests we check the type definition directly.
      expect(type.type_definition.attributes[:password][:sensitive]).to be(true)
    end

    it 'accepts a plain String' do
      resource = type.new(name: 'myremote', password: 'hunter2')
      expect(resource[:password]).to eq('hunter2')
    end

    it 'accepts a Sensitive-wrapped String' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('hunter2')
      resource = type.new(name: 'myremote', password: sensitive)
      expect(resource[:password]).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
    end
  end

  describe 'optional attributes' do
    subject(:resource) { type.new(name: 'myremote') }

    [:port, :fingerprint, :use_node_proxy, :comment, :password].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end

    it 'can be declared ensure => absent without password' do
      expect { type.new(name: 'myremote', ensure: 'absent') }.not_to raise_error
    end
  end

  describe 'use_node_proxy attribute' do
    it 'accepts true' do
      resource = type.new(name: 'myremote', use_node_proxy: true)
      expect(resource[:use_node_proxy]).to eq(:true)
    end

    it 'accepts false' do
      resource = type.new(name: 'myremote', use_node_proxy: false)
      expect(resource[:use_node_proxy]).to eq(:false)
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        name:        'myremote',
        host:        'pbs.example.com',
        port:        8007,
        userid:      'user@pbs',
        password:    'hunter2',
        fingerprint: 'AA:BB:CC',
        comment:     'test remote',
      )
    end

    it { expect(resource[:name]).to eq('myremote') }
    it { expect(resource[:host]).to eq('pbs.example.com') }
    it { expect(resource[:port]).to eq(8007) }
    it { expect(resource[:userid]).to eq('user@pbs') }
    it { expect(resource[:password]).to eq('hunter2') }
    it { expect(resource[:fingerprint]).to eq('AA:BB:CC') }
    it { expect(resource[:comment]).to eq('test remote') }
  end
end
