# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_node_config'

RSpec.describe 'pbs_node_config type' do
  let(:type) { Puppet::Type.type(:pbs_node_config) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :node as the namevar' do
    expect(type.key_attributes).to include(:node)
  end

  describe 'node namevar validation' do
    it 'accepts a short hostname' do
      expect { type.new(node: 'pbs-01') }.not_to raise_error
    end

    it 'rejects an FQDN (node must be the short hostname)' do
      expect { type.new(node: 'pbs.example.com') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a name starting with a hyphen' do
      expect { type.new(node: '-bad') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a name with a slash (URL path injection)' do
      expect { type.new(node: 'bad/../node') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'description munging' do
    it 'chomps a trailing newline so manifests with heredocs do not drift' do
      resource = type.new(node: 'localhost', description: "# Notes\n\nManaged by Puppet.\n")
      expect(resource[:description]).to eq("# Notes\n\nManaged by Puppet.")
    end

    it 'leaves a description without trailing newline unchanged' do
      resource = type.new(node: 'localhost', description: 'Plain notes')
      expect(resource[:description]).to eq('Plain notes')
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(node: 'localhost', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(node: 'localhost', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(node: 'localhost') }

    [:description, :email_from, :http_proxy, :default_lang, :task_log_max_days, :consent_text, :location].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end

  describe 'all attributes settable' do
    subject(:resource) do
      type.new(
        node:               'localhost',
        description:        "# My PBS Server\n\nManaged by Puppet.",
        email_from:         'pbs@example.com',
        http_proxy:         'http://proxy.example.com:3128',
        default_lang:       'en',
        task_log_max_days:  365,
        consent_text:       'Authorized use only.',
        location:           'DC1-Rack-A',
      )
    end

    it { expect(resource[:node]).to eq('localhost') }
    it { expect(resource[:description]).to eq("# My PBS Server\n\nManaged by Puppet.") }
    it { expect(resource[:email_from]).to eq('pbs@example.com') }
    it { expect(resource[:http_proxy]).to eq('http://proxy.example.com:3128') }
    it { expect(resource[:default_lang]).to eq('en') }
    it { expect(resource[:task_log_max_days]).to eq(365) }
    it { expect(resource[:consent_text]).to eq('Authorized use only.') }
    it { expect(resource[:location]).to eq('DC1-Rack-A') }
  end
end
