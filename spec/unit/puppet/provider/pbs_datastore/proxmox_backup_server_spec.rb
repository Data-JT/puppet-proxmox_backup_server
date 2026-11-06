# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_datastore/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsDatastore::ProxmoxBackupServer do
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
    allow(mock_type).to receive(:namevars).and_return([:name])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
    allow(mock_transport).to receive(:wait_for_task)
  end

  describe '#get' do
    it 'returns [] when the API returns nil' do
      allow(mock_transport).to receive(:get).with(context, '/config/datastore', any_args).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the API returns an empty array' do
      allow(mock_transport).to receive(:get).with(context, '/config/datastore', any_args).and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'maps the API response to Puppet resource hashes' do
      api_data = [
        {
          'name'        => 'backup',
          'path'        => '/mnt/backup',
          'comment'     => 'main store',
          'gc-schedule' => 'daily',
        },
      ]
      allow(mock_transport).to receive(:get).with(context, '/config/datastore', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          name:        'backup',
          path:        '/mnt/backup',
          comment:     'main store',
          gc_schedule: 'daily',
          ensure:      'present',
        ),
      )
    end

    it 'does not map deprecated datastore retention attributes' do
      api_data = [{
        'name'         => 'store',
        'path'         => '/mnt/store',
        'keep-hourly'  => 24,
        'keep-weekly'  => 4,
        'keep-monthly' => 3,
        'keep-yearly'  => 1,
      }]
      allow(mock_transport).to receive(:get).with(context, '/config/datastore', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result.first).not_to include(:keep_hourly, :keep_weekly, :keep_monthly, :keep_yearly)
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end
  end

  describe '#create' do
    let(:upid) { 'UPID:pbs:00000001:00000001:00000001:00000001:create-datastore:backup:puppet@pbs!puppet:' }

    before(:each) do
      allow(mock_transport).to receive(:post).and_return(upid)
    end

    it 'never sends a delete parameter on create even when delete_properties are declared' do
      should = { name: 'backup', path: '/mnt/backup', delete_properties: ['comment'], ensure: 'present' }
      expect(mock_transport).to receive(:post).with(context, '/config/datastore', hash_excluding('delete')).and_return(upid)
      provider.create(context, 'backup', should)
    end

    it 'posts to /config/datastore with name and path' do
      should = { name: 'backup', path: '/mnt/backup', ensure: 'present', comment: nil }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/config/datastore')
        expect(body).to include('name' => 'backup', 'path' => '/mnt/backup')
        upid
      end
      provider.create(context, 'backup', should)
    end

    it 'excludes ensure from the POST body' do
      should = { name: 'backup', path: '/mnt/backup', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
        upid
      end
      provider.create(context, 'backup', should)
    end

    it 'excludes nil attributes from the POST body' do
      should = { name: 'backup', path: '/mnt/backup', ensure: 'present', comment: nil, gc_schedule: nil }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('comment')
        expect(body).not_to have_key('gc-schedule')
        upid
      end
      provider.create(context, 'backup', should)
    end

    it 'waits for the async task to complete' do
      should = { name: 'backup', path: '/mnt/backup', ensure: 'present' }
      expect(mock_transport).to receive(:wait_for_task).with(context, upid)
      provider.create(context, 'backup', should)
    end

    it 'propagates task failure as ResourceError' do
      should = { name: 'backup', path: '/mnt/backup', ensure: 'present' }
      allow(mock_transport).to receive(:wait_for_task).and_raise(
        Puppet::ResourceError, 'PBS async task failed: datastore path not empty'
      )
      expect { provider.create(context, 'backup', should) }
        .to raise_error(Puppet::ResourceError, %r{datastore path not empty})
    end
  end

  describe '#update' do
    it 'sends delete_properties as the PBS delete list' do
      should = { name: 'backup', delete_properties: ['comment', 'gc-schedule'], ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to eq('delete' => ['comment', 'gc-schedule'])
      end
      provider.update(context, 'backup', should)
    end

    it 'delegates delete_properties comparison to the base implementation' do
      should = { delete_properties: ['gc-schedule'] }
      expect(provider.insync?(context, 'backup', :delete_properties, { gc_schedule: 'daily' }, should)).to be(false)
      expect(provider.insync?(context, 'backup', :delete_properties, {}, should)).to be(true)
    end

    it 'puts to /config/datastore/{name}' do
      should = { name: 'backup', path: '/mnt/backup', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/config/datastore/backup')
      end
      provider.update(context, 'backup', should)
    end

    it 'raises when the manifest path differs from the existing datastore path (create-only)' do
      allow(mock_transport).to receive(:get).with(context, '/config/datastore', any_args)
                                            .and_return([{ 'name' => 'backup', 'path' => '/mnt/backup' }])
      provider.get(context)

      should = { name: 'backup', path: '/mnt/elsewhere', ensure: 'present' }
      expect(mock_transport).not_to receive(:put)
      expect { provider.update(context, 'backup', should) }
        .to raise_error(Puppet::ResourceError, %r{path is create-only.*'/mnt/backup'.*'/mnt/elsewhere'}m)
    end

    it 'updates normally when the manifest path matches the existing path' do
      allow(mock_transport).to receive(:get).with(context, '/config/datastore', any_args)
                                            .and_return([{ 'name' => 'backup', 'path' => '/mnt/backup' }])
      provider.get(context)

      should = { name: 'backup', path: '/mnt/backup', gc_schedule: 'weekly', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, body|
        expect(path).to eq('/config/datastore/backup')
        expect(body).to include('gc-schedule' => 'weekly')
        expect(body).not_to have_key('path')
      end
      provider.update(context, 'backup', should)
    end

    it 'excludes name, path, ensure, and nil values from the PUT body' do
      should = {
        name:        'backup',
        path:        '/mnt/backup',
        ensure:      'present',
        comment:     nil,
        gc_schedule: 'weekly',
      }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('gc-schedule' => 'weekly')
        expect(body).not_to have_key('path')
        expect(body).not_to have_key('name')
        expect(body).not_to have_key('ensure')
        expect(body).not_to have_key('comment')
      end
      provider.update(context, 'backup', should)
    end
  end

  describe '#delete' do
    let(:upid) { 'UPID:pbs:00000001:00000001:00000001:00000001:delete-datastore:mystore:puppet@pbs!puppet:' }

    it 'sends DELETE to /config/datastore/{name}' do
      expect(mock_transport).to receive(:delete).with(context, '/config/datastore/mystore').and_return(upid)
      provider.delete(context, 'mystore')
    end

    it 'waits for the async task to complete' do
      allow(mock_transport).to receive(:delete).and_return(upid)
      expect(mock_transport).to receive(:wait_for_task).with(context, upid)
      provider.delete(context, 'mystore')
    end
  end
end
