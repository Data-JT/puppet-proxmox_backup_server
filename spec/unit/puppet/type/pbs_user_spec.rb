# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_user'

RSpec.describe 'pbs_user type' do
  let(:type) { Puppet::Type.type(:pbs_user) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :userid as the namevar' do
    expect(type.key_attributes).to include(:userid)
  end

  describe 'userid namevar validation' do
    it 'accepts user@realm' do
      expect { type.new(userid: 'john.doe-1@pbs') }.not_to raise_error
    end

    it 'rejects a userid without a realm' do
      expect { type.new(userid: 'useronly') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a userid with whitespace' do
      expect { type.new(userid: 'john doe@pbs') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a userid with a slash (URL path injection)' do
      expect { type.new(userid: 'john/../x@pbs') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a token-style userid with an exclamation mark' do
      expect { type.new(userid: 'john!token@pbs') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(userid: 'user@pbs', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(userid: 'user@pbs', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'enable attribute' do
    it 'defaults to true' do
      resource = type.new(userid: 'user@pbs')
      expect(resource[:enable]).to eq(:true)
    end

    it 'accepts false' do
      resource = type.new(userid: 'user@pbs', enable: false)
      expect(resource[:enable]).to eq(:false)
    end
  end

  describe 'optional attributes' do
    subject(:resource) { type.new(userid: 'user@pbs') }

    [:comment, :email, :expire, :firstname, :lastname, :password].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end

    it 'can be declared ensure => absent without password' do
      expect { type.new(userid: 'user@pbs', ensure: 'absent') }.not_to raise_error
    end
  end

  describe 'password attribute' do
    it 'is a property so password drift can be detected' do
      expect(type.attrtype(:password)).to eq(:property)
    end

    it 'is marked sensitive in the type definition' do
      expect(type.type_definition.attributes[:password][:sensitive]).to be(true)
    end

    it 'accepts a plain String' do
      resource = type.new(userid: 'user@pbs', password: 'secret')
      expect(resource[:password]).to eq('secret')
    end

    it 'accepts a Sensitive-wrapped String' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret')
      resource = type.new(userid: 'user@pbs', password: sensitive)
      expect(resource[:password]).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
    end

    # The realm restriction is enforced in the provider, not with a
    # Puppet::Type.validate block. Puppet::Type.validate is a define_method
    # (type.rb:2250), so it REPLACES the Resource API's own validate rather
    # than chaining -- and that is where @missing_attrs is initialised. With it
    # clobbered, retrieve hits raise_missing_attrs, which builds its message
    # with @missing_attrs.join BEFORE checking the guard (resource_api.rb:376),
    # so every resource of this type died on nil.join. See the provider specs
    # for the enforcement itself.
    it 'accepts a password on a non-@pbs realm user at the type level' do
      expect { type.new(userid: 'svc@pam', password: 'secret') }.not_to raise_error
    end

    it 'initialises the Resource API @missing_attrs list' do
      resource = type.new(userid: 'svc@pbs')
      expect(resource.instance_variable_get(:@missing_attrs)).to eq([])
    end

    it 'can build the missing-attribute message without raising' do
      resource = type.new(userid: 'svc@pbs')
      expect { resource.send(:raise_missing_attrs) }.not_to raise_error
    end

    it 'allows non-@pbs realm users without a password' do
      expect { type.new(userid: 'svc@pam') }.not_to raise_error
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        userid:    'john@pbs',
        comment:   'John Doe',
        email:     'john@example.com',
        enable:    false,
        expire:    1_700_000_000,
        firstname: 'John',
        lastname:  'Doe',
      )
    end

    it { expect(resource[:userid]).to eq('john@pbs') }
    it { expect(resource[:comment]).to eq('John Doe') }
    it { expect(resource[:email]).to eq('john@example.com') }
    it { expect(resource[:enable]).to eq(:false) }
    it { expect(resource[:expire]).to eq(1_700_000_000) }
    it { expect(resource[:firstname]).to eq('John') }
    it { expect(resource[:lastname]).to eq('Doe') }
  end
end
