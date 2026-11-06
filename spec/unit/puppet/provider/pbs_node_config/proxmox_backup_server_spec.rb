# frozen_string_literal: true

require 'spec_helper'
require 'socket'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_node_config/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsNodeConfig::ProxmoxBackupServer do
  subject(:provider) { described_class.new }

  let(:mock_transport) { instance_double('Puppet::Transport::ProxmoxBackupServer') }
  let(:mock_type)      { instance_double('Puppet::ResourceApi::Type') }
  let(:context) do
    instance_double(
      'Puppet::ResourceApi::BaseContext',
      type: mock_type,
    )
  end

  before(:each) do
    allow(provider).to receive(:pbs_transport).and_return(mock_transport)
    allow(mock_type).to receive(:namevars).and_return([:node])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
    allow(Socket).to receive(:gethostname).and_return('pbs.example.com')
  end

  describe '#get' do
    it 'derives the node name from the local hostname (short form)' do
      expect(mock_transport).to receive(:get).with(context, '/nodes/pbs/config', any_args).and_return({})
      provider.get(context)
    end

    it 'uses the short hostname when gethostname returns an FQDN' do
      allow(Socket).to receive(:gethostname).and_return('pbs.example.com')
      allow(mock_transport).to receive(:get).with(context, '/nodes/pbs/config', any_args).and_return({})
      result = provider.get(context)
      expect(result.first[:node]).to eq('pbs')
    end

    it 'returns a single resource hash with ensure: present' do
      allow(mock_transport).to receive(:get).with(context, '/nodes/pbs/config', any_args).and_return({})
      result = provider.get(context)
      expect(result.length).to eq(1)
      expect(result.first[:ensure]).to eq('present')
    end

    it 'maps all config fields correctly' do
      api_data = {
        'description'       => "# My Server\n\nNotes here.",
        'email-from'        => 'pbs@example.com',
        'http-proxy'        => 'http://proxy:3128',
        'default-lang'      => 'en',
        'task-log-max-days' => 365,
        'consent-text'      => 'Authorized use only.',
        'location'          => 'DC1',
      }
      allow(mock_transport).to receive(:get).with(context, '/nodes/pbs/config', any_args).and_return(api_data)

      result = provider.get(context).first
      expect(result[:description]).to eq("# My Server\n\nNotes here.")
      expect(result[:email_from]).to eq('pbs@example.com')
      expect(result[:http_proxy]).to eq('http://proxy:3128')
      expect(result[:default_lang]).to eq('en')
      expect(result[:task_log_max_days]).to eq(365)
      expect(result[:consent_text]).to eq('Authorized use only.')
      expect(result[:location]).to eq('DC1')
    end

    it 'strips trailing newline from description returned by the API' do
      allow(mock_transport).to receive(:get).with(context, '/nodes/pbs/config', any_args)
                                            .and_return('description' => "Test Note #1\n")
      result = provider.get(context).first
      expect(result[:description]).to eq('Test Note #1')
    end

    it 'handles nil config response gracefully' do
      allow(mock_transport).to receive(:get).with(context, '/nodes/pbs/config', any_args).and_return(nil)
      result = provider.get(context)
      expect(result.first[:node]).to eq('pbs')
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end
  end

  describe '#create' do
    it 'delegates to update' do
      should = { node: 'pbs', description: 'Notes', ensure: 'present' }
      expect(mock_transport).to receive(:put).with(context, '/nodes/pbs/config', anything)
      provider.create(context, 'pbs', should)
    end

    it 'raises when the title is not the local node name' do
      should = { node: 'localhost', description: 'Notes', ensure: 'present' }
      expect(mock_transport).not_to receive(:put)
      expect { provider.create(context, 'localhost', should) }
        .to raise_error(Puppet::ResourceError, %r{title must be the local node name 'pbs', got 'localhost'})
    end
  end

  describe '#canonicalize' do
    it 'chomps a trailing newline from description' do
      resources = [{ node: 'pbs', description: "Notes\n", ensure: 'present' }]
      expect(provider.canonicalize(context, resources).first[:description]).to eq('Notes')
    end

    it 'leaves other values and nil descriptions untouched' do
      resources = [{ node: 'pbs', description: nil, location: 'DC1', ensure: 'present' }]
      result = provider.canonicalize(context, resources).first
      expect(result[:description]).to be_nil
      expect(result[:location]).to eq('DC1')
    end

    it 'does not mutate the input resources' do
      resources = [{ node: 'pbs', description: "Notes\n", ensure: 'present' }]
      provider.canonicalize(context, resources)
      expect(resources.first[:description]).to eq("Notes\n")
    end
  end

  describe '#update' do
    it 'sends delete_properties as the PBS delete list' do
      should = { node: 'pbs', delete_properties: ['http-proxy', 'email-from'], ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to eq('delete' => ['http-proxy', 'email-from'])
      end
      provider.update(context, 'pbs', should)
    end

    it 'puts to /nodes/{node}/config using the namevar' do
      should = { node: 'pbs', description: 'Updated notes', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/nodes/pbs/config')
      end
      provider.update(context, 'pbs', should)
    end

    it 'excludes node and ensure from the PUT body' do
      should = { node: 'pbs', description: 'Notes', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('node')
        expect(body).not_to have_key('ensure')
      end
      provider.update(context, 'pbs', should)
    end

    it 'sends description in the PUT body' do
      should = { node: 'pbs', description: "# Notes\n\nHello.", ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('description' => "# Notes\n\nHello.")
      end
      provider.update(context, 'pbs', should)
    end

    it 'uses kebab-case keys in the PUT body' do
      should = {
        node: 'pbs', ensure: 'present',
        email_from: 'pbs@example.com', http_proxy: 'http://proxy:3128',
        default_lang: 'en', task_log_max_days: 365,
        consent_text: 'Authorized.', location: 'DC1',
      }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include(
          'email-from'        => 'pbs@example.com',
          'http-proxy'        => 'http://proxy:3128',
          'default-lang'      => 'en',
          'task-log-max-days' => 365,
          'consent-text'      => 'Authorized.',
          'location'          => 'DC1',
        )
        expect(body).not_to have_key('email_from')
        expect(body).not_to have_key('http_proxy')
      end
      provider.update(context, 'pbs', should)
    end

    it 'excludes nil optional attributes from the PUT body' do
      should = { node: 'pbs', description: 'Notes', email_from: nil, http_proxy: nil, ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('email-from')
        expect(body).not_to have_key('http-proxy')
      end
      provider.update(context, 'pbs', should)
    end

    it 'raises when the title is not the local node name' do
      should = { node: 'otherhost', description: 'Notes', ensure: 'present' }
      expect(mock_transport).not_to receive(:put)
      expect { provider.update(context, 'otherhost', should) }
        .to raise_error(Puppet::ResourceError, %r{title must be the local node name 'pbs', got 'otherhost'})
    end
  end

  describe '#delete' do
    it 'raises because the node config cannot be deleted' do
      expect(mock_transport).not_to receive(:delete)
      expect { provider.delete(context, 'pbs') }
        .to raise_error(Puppet::ResourceError, %r{cannot be deleted.*remove the resource from the manifest}m)
    end

    it 'raises when the title is not the local node name' do
      expect { provider.delete(context, 'otherhost') }
        .to raise_error(Puppet::ResourceError, %r{title must be the local node name 'pbs'})
    end
  end
end
