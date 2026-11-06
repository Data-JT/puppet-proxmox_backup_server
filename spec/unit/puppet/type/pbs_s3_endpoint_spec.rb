# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_s3_endpoint'

RSpec.describe 'pbs_s3_endpoint type' do
  let(:type) { Puppet::Type.type(:pbs_s3_endpoint) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :id as the namevar' do
    expect(type.key_attributes).to include(:id)
  end

  describe 'id namevar validation' do
    it 'accepts a PBS safe-ID' do
      expect { type.new(id: 'aws_primary-1.a', endpoint: 'https://s3.example.com', access_key: 'AK') }.not_to raise_error
    end

    it 'rejects an id with a slash (URL path injection)' do
      expect { type.new(id: 'bad/../ep', endpoint: 'https://s3.example.com', access_key: 'AK') }
        .to raise_error(Puppet::ResourceError)
    end

    it 'rejects an id with whitespace' do
      expect { type.new(id: 'bad ep', endpoint: 'https://s3.example.com', access_key: 'AK') }
        .to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(id: 'my-s3', endpoint: 'https://s3.amazonaws.com', access_key: 'AK', secret_key: 'sk', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(id: 'my-s3', endpoint: 'https://s3.amazonaws.com', access_key: 'AK', secret_key: 'sk', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'secret_key parameter' do
    # A property, not a parameter: :parameter removed enforcement entirely,
    # so editing only the secret key in Hiera changed nothing on the node.
    it 'is a property, so Puppet enforces it' do
      expect(type.attrtype(:secret_key)).to eq(:property)
    end

    it 'is marked sensitive' do
      expect(type.type_definition.attributes[:secret_key][:sensitive]).to be(true)
    end

    it 'accepts a plain String' do
      expect { type.new(id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK', secret_key: 'mysecret') }.not_to raise_error
    end

    it 'accepts a Sensitive-wrapped String' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('mysecret')
      expect { type.new(id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK', secret_key: sensitive) }.not_to raise_error
    end

    it 'is optional (create-only; enforced by the provider at creation time)' do
      expect { type.new(id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK') }.not_to raise_error
    end

    it 'can be declared ensure => absent without secret_key' do
      expect { type.new(id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK', ensure: 'absent') }.not_to raise_error
    end
  end

  describe 'path_style attribute' do
    it 'accepts true' do
      resource = type.new(id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK', secret_key: 'sk', path_style: true)
      expect(resource[:path_style]).to eq(:true)
    end

    it 'accepts false' do
      resource = type.new(id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK', secret_key: 'sk', path_style: false)
      expect(resource[:path_style]).to eq(:false)
    end

    it 'is nil when not set' do
      resource = type.new(id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK', secret_key: 'sk')
      expect(resource[:path_style]).to be_nil
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(id: 'ep', endpoint: 'https://s3.example.com', access_key: 'AK', secret_key: 'sk') }

    [:port, :region, :fingerprint, :path_style, :rate_in, :burst_in, :rate_out, :burst_out, :provider_quirks].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end

  describe 'all attributes settable' do
    subject(:resource) do
      type.new(
        id:              'aws-primary',
        endpoint:        'https://s3.amazonaws.com',
        access_key:      'AKIAIOSFODNN7EXAMPLE',
        secret_key:      'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        port:            443,
        region:          'us-east-1',
        fingerprint:     'AA:BB:CC',
        path_style:      false,
        rate_in:         '100 MiB',
        burst_in:        '200 MiB',
        rate_out:        '50 MiB',
        burst_out:       '104857600',
        provider_quirks: 'virtual-hosted-style',
      )
    end

    it { expect(resource[:id]).to eq('aws-primary') }
    it { expect(resource[:endpoint]).to eq('https://s3.amazonaws.com') }
    it { expect(resource[:access_key]).to eq('AKIAIOSFODNN7EXAMPLE') }
    it { expect(resource[:port]).to eq(443) }
    it { expect(resource[:region]).to eq('us-east-1') }
    it { expect(resource[:fingerprint]).to eq('AA:BB:CC') }
    it { expect(resource[:path_style]).to eq(:false) }
    it { expect(resource[:rate_in]).to eq('100 MiB') }
    it { expect(resource[:burst_in]).to eq('200 MiB') }
    it { expect(resource[:rate_out]).to eq('50 MiB') }
    it { expect(resource[:burst_out]).to eq('104857600') }
    it { expect(resource[:provider_quirks]).to eq('virtual-hosted-style') }
  end
end
