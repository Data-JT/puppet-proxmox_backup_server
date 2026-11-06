# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_api_token'

RSpec.describe 'pbs_api_token type' do
  let(:type) { Puppet::Type.type(:pbs_api_token) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :tokenid as the namevar' do
    expect(type.key_attributes).to include(:tokenid)
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(tokenid: 'puppet@pbs!mytoken', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(tokenid: 'puppet@pbs!mytoken', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'tokenid attribute' do
    it 'accepts user@realm!tokenname format' do
      expect { type.new(tokenid: 'puppet@pbs!mytoken') }.not_to raise_error
    end

    it 'accepts pam realm' do
      expect { type.new(tokenid: 'root@pam!admin-token') }.not_to raise_error
    end

    it 'rejects a tokenid without a token name' do
      expect { type.new(tokenid: 'puppet@pbs') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a tokenid without a realm' do
      expect { type.new(tokenid: 'puppet!mytoken') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a tokenid containing a slash' do
      expect { type.new(tokenid: 'puppet@pbs!../evil') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a tokenid containing whitespace' do
      expect { type.new(tokenid: 'puppet@pbs!my token') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        tokenid: 'puppet@pbs!mytoken',
        comment: 'Puppet automation token',
        enable:  true,
        expire:  1_893_456_000,
        secret_file: '/etc/puppetlabs/puppet/pbs-token.secret',
      )
    end

    it { expect(resource[:tokenid]).to eq('puppet@pbs!mytoken') }
    it { expect(resource[:comment]).to eq('Puppet automation token') }
    it { expect(resource[:expire]).to eq(1_893_456_000) }
    it { expect(resource[:secret_file]).to eq('/etc/puppetlabs/puppet/pbs-token.secret') }
  end

  describe 'secret_file parameter' do
    it 'has behaviour :parameter' do
      expect(type.attrtype(:secret_file)).to eq(:param)
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(tokenid: 'puppet@pbs!mytoken') }

    [:comment, :enable, :expire, :secret_file].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end
end
