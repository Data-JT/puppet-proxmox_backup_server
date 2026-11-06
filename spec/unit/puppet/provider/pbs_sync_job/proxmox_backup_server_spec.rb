# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_sync_job/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsSyncJob::ProxmoxBackupServer do
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
    allow(mock_type).to receive(:namevars).and_return([:id])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
  end

  describe '#get' do
    it 'returns [] when the API returns nil' do
      allow(mock_transport).to receive(:get).with(context, '/config/sync', any_args).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the API returns an empty array' do
      allow(mock_transport).to receive(:get).with(context, '/config/sync', any_args).and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'maps the API response to Puppet resource hashes' do
      api_data = [
        {
          'id'              => 'daily-sync',
          'store'           => 'local',
          'remote'          => 'remote-pbs',
          'remote-store'    => 'offsite',
          'schedule'        => 'daily',
          'remove-vanished' => 0,
          'comment'         => 'nightly sync',
        },
      ]
      allow(mock_transport).to receive(:get).with(context, '/config/sync', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          id:               'daily-sync',
          store:            'local',
          remote:           'remote-pbs',
          remote_store:     'offsite',
          job_schedule:     'daily',
          remove_vanished:  false,
          comment:          'nightly sync',
          ensure:           'present',
        ),
      )
    end

    it 'converts remove-vanished integer 1 to true' do
      api_data = [{ 'id' => 'j1', 'store' => 'local', 'remote' => 'r', 'remote-store' => 's', 'remove-vanished' => 1 }]
      allow(mock_transport).to receive(:get).with(context, '/config/sync', any_args).and_return(api_data)
      expect(provider.get(context).first[:remove_vanished]).to be(true)
    end

    it 'converts remove-vanished integer 0 to false' do
      api_data = [{ 'id' => 'j1', 'store' => 'local', 'remote' => 'r', 'remote-store' => 's', 'remove-vanished' => 0 }]
      allow(mock_transport).to receive(:get).with(context, '/config/sync', any_args).and_return(api_data)
      expect(provider.get(context).first[:remove_vanished]).to be(false)
    end

    it 'maps remote-store using dash-to-underscore translation' do
      api_data = [{ 'id' => 'j1', 'store' => 'local', 'remote' => 'r', 'remote-store' => 'offsite' }]
      allow(mock_transport).to receive(:get).with(context, '/config/sync', any_args).and_return(api_data)
      expect(provider.get(context).first[:remote_store]).to eq('offsite')
    end

    it 'maps remote-ns, ns, max-depth, sync-direction, owner, and group-filter' do
      api_data = [{
        'id' => 'j1', 'store' => 'local', 'remote' => 'r', 'remote-store' => 's',
        'remote-ns' => 'vm/100', 'ns' => 'imported', 'max-depth' => 2,
        'sync-direction' => 'pull', 'owner' => 'puppet@pbs', 'group-filter' => ['type:vm'],
      }]
      allow(mock_transport).to receive(:get).with(context, '/config/sync', any_args).and_return(api_data)

      result = provider.get(context).first
      expect(result[:remote_ns]).to eq('vm/100')
      expect(result[:ns]).to eq('imported')
      expect(result[:max_depth]).to eq(2)
      expect(result[:sync_direction]).to eq('pull')
      expect(result[:owner]).to eq('puppet@pbs')
      expect(result[:group_filter]).to eq(['type:vm'])
    end

    it 'passes a multi-element group-filter array through unchanged' do
      api_data = [{ 'id' => 'j1', 'store' => 'local', 'remote' => 'r', 'remote-store' => 's',
                    'group-filter' => ['type:vm', 'group:vm/100'] }]
      allow(mock_transport).to receive(:get).with(context, '/config/sync', any_args).and_return(api_data)
      expect(provider.get(context).first[:group_filter]).to eq(['type:vm', 'group:vm/100'])
    end

    it 'maps transfer_last and worker_threads as integers' do
      api_data = [{ 'id' => 'j1', 'store' => 'local', 'remote' => 'r', 'remote-store' => 's',
                    'transfer-last' => 3, 'worker-threads' => 4 }]
      allow(mock_transport).to receive(:get).with(context, '/config/sync', any_args).and_return(api_data)

      result = provider.get(context).first
      expect(result[:transfer_last]).to eq(3)
      expect(result[:worker_threads]).to eq(4)
    end

    it 'converts resync-corrupt, encrypted-only, and verified-only booleans' do
      api_data = [{ 'id' => 'j1', 'store' => 'local', 'remote' => 'r', 'remote-store' => 's',
                    'resync-corrupt' => true, 'encrypted-only' => false, 'verified-only' => true }]
      allow(mock_transport).to receive(:get).with(context, '/config/sync', any_args).and_return(api_data)

      result = provider.get(context).first
      expect(result[:resync_corrupt]).to be(true)
      expect(result[:encrypted_only]).to be(false)
      expect(result[:verified_only]).to be(true)
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end
  end

  describe '#create' do
    it 'posts to /config/sync with id, store, remote, and remote-store' do
      should = {
        id: 'daily-sync', store: 'local', remote: 'remote-pbs',
        remote_store: 'offsite', ensure: 'present', remove_vanished: false,
        job_schedule: nil, comment: nil,
      }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/config/sync')
        expect(body).to include('id' => 'daily-sync', 'store' => 'local',
                                'remote' => 'remote-pbs', 'remote-store' => 'offsite')
      end
      provider.create(context, 'daily-sync', should)
    end

    it 'excludes ensure from the POST body' do
      should = { id: 'j1', store: 'local', remote: 'r', remote_store: 's', ensure: 'present', remove_vanished: false }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'j1', should)
    end

    it 'excludes nil optional attributes from the POST body' do
      should = { id: 'j1', store: 'local', remote: 'r', remote_store: 's',
                 ensure: 'present', remove_vanished: false, job_schedule: nil, comment: nil }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('schedule')
        expect(body).not_to have_key('comment')
      end
      provider.create(context, 'j1', should)
    end

    it 'sends remove_vanished :true as a boolean in the POST body' do
      should = { id: 'j1', store: 'local', remote: 'r', remote_store: 's',
                 ensure: 'present', remove_vanished: :true }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['remove-vanished']).to eq(true)
      end
      provider.create(context, 'j1', should)
    end

    it 'sends remove_vanished :false as a boolean in the POST body' do
      should = { id: 'j1', store: 'local', remote: 'r', remote_store: 's',
                 ensure: 'present', remove_vanished: :false }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['remove-vanished']).to eq(false)
      end
      provider.create(context, 'j1', should)
    end

    it 'sends new fields with correct hyphenated keys' do
      should = {
        id: 'j1', store: 'local', remote: 'r', remote_store: 's', ensure: 'present',
        remove_vanished: false, remote_ns: 'vm/100', ns: 'imported', max_depth: 2,
        sync_direction: 'pull', owner: 'puppet@pbs', group_filter: ['type:vm', 'group:vm/100'],
        transfer_last: 3, worker_threads: 4,
        resync_corrupt: :true, encrypted_only: :false, verified_only: :true,
      }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include(
          'remote-ns'      => 'vm/100',
          'ns'             => 'imported',
          'max-depth'      => 2,
          'sync-direction' => 'pull',
          'owner'          => 'puppet@pbs',
          'group-filter'   => ['type:vm', 'group:vm/100'],
          'transfer-last'  => 3,
          'worker-threads' => 4,
          'resync-corrupt' => true,
          'encrypted-only' => false,
          'verified-only'  => true,
        )
      end
      provider.create(context, 'j1', should)
    end
  end

  describe '#update' do
    it 'puts to /config/sync/{id}' do
      should = { id: 'daily-sync', store: 'local', remote: 'r', remote_store: 's',
                 ensure: 'present', remove_vanished: false }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/config/sync/daily-sync')
      end
      provider.update(context, 'daily-sync', should)
    end

    it 'excludes id, ensure, and nil values from the PUT body' do
      should = {
        id: 'daily-sync', store: 'local', remote: 'r', remote_store: 's',
        ensure: 'present', remove_vanished: false, job_schedule: 'weekly', comment: nil,
      }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('store' => 'local', 'schedule' => 'weekly')
        expect(body).not_to have_key('id')
        expect(body).not_to have_key('ensure')
        expect(body).not_to have_key('comment')
      end
      provider.update(context, 'daily-sync', should)
    end

    it 'uses the hyphenated PBS key remote-store in the PUT body' do
      should = { id: 'j1', store: 'local', remote: 'r', remote_store: 'offsite',
                 ensure: 'present', remove_vanished: false }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('remote-store' => 'offsite')
        expect(body).not_to have_key('remote_store')
      end
      provider.update(context, 'j1', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /config/sync/{id}' do
      expect(mock_transport).to receive(:delete).with(context, '/config/sync/daily-sync')
      provider.delete(context, 'daily-sync')
    end
  end
end
