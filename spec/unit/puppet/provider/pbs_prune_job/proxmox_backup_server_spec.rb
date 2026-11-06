# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_prune_job/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsPruneJob::ProxmoxBackupServer do
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
      allow(mock_transport).to receive(:get).with(context, '/config/prune', any_args).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the API returns an empty array' do
      allow(mock_transport).to receive(:get).with(context, '/config/prune', any_args).and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'maps the API response to Puppet resource hashes' do
      api_data = [
        {
          'id'           => 'daily-prune',
          'store'        => 'local',
          'schedule'     => 'daily',
          'keep-last'    => 5,
          'keep-daily'   => 7,
          'comment'      => 'keep a week',
        },
      ]
      allow(mock_transport).to receive(:get).with(context, '/config/prune', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          id:         'daily-prune',
          store:      'local',
          job_schedule: 'daily',
          keep_last:  5,
          keep_daily: 7,
          comment:    'keep a week',
          ensure:     'present',
        ),
      )
    end

    it 'maps all keep-* attributes using dash-to-underscore translation' do
      api_data = [{
        'id'           => 'j1',
        'store'        => 'local',
        'keep-hourly'  => 24,
        'keep-weekly'  => 4,
        'keep-monthly' => 3,
        'keep-yearly'  => 1,
      }]
      allow(mock_transport).to receive(:get).with(context, '/config/prune', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result.first).to include(
        keep_hourly:  24,
        keep_weekly:  4,
        keep_monthly: 3,
        keep_yearly:  1,
      )
    end

    it 'maps the ns attribute' do
      api_data = [{ 'id' => 'j1', 'store' => 'local', 'ns' => 'team/project' }]
      allow(mock_transport).to receive(:get).with(context, '/config/prune', any_args).and_return(api_data)
      expect(provider.get(context).first[:ns]).to eq('team/project')
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end
  end

  describe '#create' do
    it 'posts to /config/prune with id, store, and schedule' do
      should = { id: 'daily-prune', store: 'local', job_schedule: 'daily',
                 ensure: 'present', ns: nil, keep_last: nil, keep_hourly: nil,
                 keep_daily: nil, keep_weekly: nil, keep_monthly: nil,
                 keep_yearly: nil, comment: nil }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/config/prune')
        expect(body).to include('id' => 'daily-prune', 'store' => 'local', 'schedule' => 'daily')
      end
      provider.create(context, 'daily-prune', should)
    end

    it 'excludes ensure from the POST body' do
      should = { id: 'j1', store: 'local', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'j1', should)
    end

    it 'excludes nil keep-* attributes from the POST body' do
      should = { id: 'j1', store: 'local', ensure: 'present',
                 keep_last: nil, keep_hourly: nil, keep_daily: nil }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('keep-last')
        expect(body).not_to have_key('keep-hourly')
        expect(body).not_to have_key('keep-daily')
      end
      provider.create(context, 'j1', should)
    end

    it 'includes keep-* values using hyphenated PBS keys' do
      should = { id: 'j1', store: 'local', ensure: 'present',
                 keep_last: 3, keep_daily: 7, keep_weekly: 4 }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('keep-last' => 3, 'keep-daily' => 7, 'keep-weekly' => 4)
        expect(body).not_to have_key('keep_last')
      end
      provider.create(context, 'j1', should)
    end
  end

  describe '#update' do
    it 'puts to /config/prune/{id}' do
      should = { id: 'daily-prune', store: 'local', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/config/prune/daily-prune')
      end
      provider.update(context, 'daily-prune', should)
    end

    it 'excludes id, ensure, and nil values from the PUT body' do
      should = {
        id: 'daily-prune', store: 'local', ensure: 'present',
        job_schedule: 'weekly', comment: nil, keep_last: 5, keep_daily: nil,
      }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('store' => 'local', 'schedule' => 'weekly', 'keep-last' => 5)
        expect(body).not_to have_key('id')
        expect(body).not_to have_key('ensure')
        expect(body).not_to have_key('comment')
        expect(body).not_to have_key('keep-daily')
      end
      provider.update(context, 'daily-prune', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /config/prune/{id}' do
      expect(mock_transport).to receive(:delete).with(context, '/config/prune/daily-prune')
      provider.delete(context, 'daily-prune')
    end
  end
end
