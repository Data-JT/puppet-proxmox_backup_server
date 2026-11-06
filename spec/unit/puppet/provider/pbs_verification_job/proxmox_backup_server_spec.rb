# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_verification_job/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsVerificationJob::ProxmoxBackupServer do
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
      allow(mock_transport).to receive(:get).with(context, '/config/verify', any_args).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the API returns an empty array' do
      allow(mock_transport).to receive(:get).with(context, '/config/verify', any_args).and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'maps the API response to Puppet resource hashes' do
      api_data = [
        {
          'id'              => 'weekly-verify',
          'store'           => 'local',
          'schedule'        => 'weekly',
          'outdated-after'  => 30,
          'ignore-verified' => 1,
          'comment'         => 'weekly check',
        },
      ]
      allow(mock_transport).to receive(:get).with(context, '/config/verify', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          id:               'weekly-verify',
          store:            'local',
          job_schedule:     'weekly',
          outdated_after:   30,
          ignore_verified:  true,
          comment:          'weekly check',
          ensure:           'present',
        ),
      )
    end

    it 'converts ignore-verified integer 1 to true' do
      api_data = [{ 'id' => 'j1', 'store' => 'local', 'ignore-verified' => 1 }]
      allow(mock_transport).to receive(:get).with(context, '/config/verify', any_args).and_return(api_data)
      expect(provider.get(context).first[:ignore_verified]).to be(true)
    end

    it 'converts ignore-verified integer 0 to false' do
      api_data = [{ 'id' => 'j1', 'store' => 'local', 'ignore-verified' => 0 }]
      allow(mock_transport).to receive(:get).with(context, '/config/verify', any_args).and_return(api_data)
      expect(provider.get(context).first[:ignore_verified]).to be(false)
    end

    it 'maps outdated-after using dash-to-underscore translation' do
      api_data = [{ 'id' => 'j1', 'store' => 'local', 'outdated-after' => 14 }]
      allow(mock_transport).to receive(:get).with(context, '/config/verify', any_args).and_return(api_data)
      expect(provider.get(context).first[:outdated_after]).to eq(14)
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end
  end

  describe '#create' do
    it 'posts to /config/verify with id and store' do
      should = { id: 'weekly-verify', store: 'local', ensure: 'present',
                 ignore_verified: false, job_schedule: nil, outdated_after: nil, comment: nil }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/config/verify')
        expect(body).to include('id' => 'weekly-verify', 'store' => 'local')
      end
      provider.create(context, 'weekly-verify', should)
    end

    it 'excludes ensure from the POST body' do
      should = { id: 'j1', store: 'local', ensure: 'present', ignore_verified: false }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'j1', should)
    end

    it 'excludes nil optional attributes from the POST body' do
      should = { id: 'j1', store: 'local', ensure: 'present',
                 ignore_verified: false, job_schedule: nil, outdated_after: nil, comment: nil }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('schedule')
        expect(body).not_to have_key('outdated-after')
        expect(body).not_to have_key('comment')
      end
      provider.create(context, 'j1', should)
    end

    it 'sends ignore_verified :true as a boolean in the POST body' do
      should = { id: 'j1', store: 'local', ensure: 'present', ignore_verified: :true }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['ignore-verified']).to eq(true)
      end
      provider.create(context, 'j1', should)
    end

    it 'sends ignore_verified :false as a boolean in the POST body' do
      should = { id: 'j1', store: 'local', ensure: 'present', ignore_verified: :false }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['ignore-verified']).to eq(false)
      end
      provider.create(context, 'j1', should)
    end

    it 'uses the hyphenated PBS key outdated-after in the POST body' do
      should = { id: 'j1', store: 'local', ensure: 'present',
                 ignore_verified: false, outdated_after: 30 }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('outdated-after' => 30)
        expect(body).not_to have_key('outdated_after')
      end
      provider.create(context, 'j1', should)
    end
  end

  describe '#update' do
    it 'puts to /config/verify/{id}' do
      should = { id: 'weekly-verify', store: 'local', ensure: 'present', ignore_verified: false }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/config/verify/weekly-verify')
      end
      provider.update(context, 'weekly-verify', should)
    end

    it 'excludes id, ensure, and nil values from the PUT body' do
      should = {
        id: 'weekly-verify', store: 'local', ensure: 'present',
        ignore_verified: true, job_schedule: 'weekly', outdated_after: nil, comment: nil,
      }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('store' => 'local', 'schedule' => 'weekly', 'ignore-verified' => true)
        expect(body).not_to have_key('id')
        expect(body).not_to have_key('ensure')
        expect(body).not_to have_key('outdated-after')
        expect(body).not_to have_key('comment')
      end
      provider.update(context, 'weekly-verify', should)
    end

    it 'uses the hyphenated PBS key ignore-verified in the PUT body' do
      should = { id: 'j1', store: 'local', ensure: 'present', ignore_verified: false }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('ignore-verified' => false)
        expect(body).not_to have_key('ignore_verified')
      end
      provider.update(context, 'j1', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /config/verify/{id}' do
      expect(mock_transport).to receive(:delete).with(context, '/config/verify/weekly-verify')
      provider.delete(context, 'weekly-verify')
    end
  end
end
