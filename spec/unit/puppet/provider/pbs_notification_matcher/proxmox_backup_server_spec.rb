# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pbs_base_provider'
require 'puppet/provider/pbs_notification_matcher/proxmox_backup_server'

RSpec.describe Puppet::Provider::PbsNotificationMatcher::ProxmoxBackupServer do
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
  end

  describe '#get' do
    it 'returns [] when the API returns nil' do
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/matchers', any_args).and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the API returns an empty array' do
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/matchers', any_args).and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'maps the API response to Puppet resource hashes' do
      api_data = [
        {
          'name'           => 'biz-hours',
          'target'         => ['smtp-relay'],
          'match-severity' => ['error'],
          'match-calendar' => ['mon-fri 09:00-17:00'],
          'match-field'    => ['exact:type=gc'],
          'mode'           => 'all',
          'invert-match'   => false,
          'disable'        => false,
          'comment'        => 'business hours',
        },
      ]
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/matchers', any_args).and_return(api_data)

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          name:            'biz-hours',
          target:          ['smtp-relay'],
          match_severity:  ['error'],
          match_calendar:  ['mon-fri 09:00-17:00'],
          match_field:     ['exact:type=gc'],
          mode:            'all',
          invert_match:    false,
          disable:         false,
          comment:         'business hours',
          ensure:          'present',
        ),
      )
    end

    it 'converts invert-match true boolean' do
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/matchers', any_args)
                                            .and_return([{ 'name' => 'm', 'invert-match' => true }])
      expect(provider.get(context).first[:invert_match]).to be(true)
    end

    it 'converts invert-match false boolean' do
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/matchers', any_args)
                                            .and_return([{ 'name' => 'm', 'invert-match' => false }])
      expect(provider.get(context).first[:invert_match]).to be(false)
    end

    it 'converts disable true boolean' do
      allow(mock_transport).to receive(:get).with(context, '/config/notifications/matchers', any_args)
                                            .and_return([{ 'name' => 'm', 'disable' => true }])
      expect(provider.get(context).first[:disable]).to be(true)
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end
  end

  describe '#create' do
    it 'posts to /config/notifications/matchers' do
      should = {
        name: 'biz-hours', target: ['smtp-relay'], match_severity: ['error'],
        mode: 'all', ensure: 'present',
      }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/config/notifications/matchers')
        expect(body).to include(
          'name'           => 'biz-hours',
          'target'         => ['smtp-relay'],
          'match-severity' => ['error'],
          'mode'           => 'all',
        )
      end
      provider.create(context, 'biz-hours', should)
    end

    it 'excludes ensure from the POST body' do
      should = { name: 'm', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'm', should)
    end

    it 'uses the hyphenated PBS key match-severity' do
      should = { name: 'm', match_severity: ['error'], ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('match-severity' => ['error'])
        expect(body).not_to have_key('match_severity')
      end
      provider.create(context, 'm', should)
    end

    it 'uses invert-match for the invert_match attribute' do
      should = { name: 'm', invert_match: true, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('invert-match' => true)
      end
      provider.create(context, 'm', should)
    end

    it 'excludes nil optional attributes from the POST body' do
      should = { name: 'm', target: nil, match_severity: nil, comment: nil, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('target')
        expect(body).not_to have_key('match-severity')
        expect(body).not_to have_key('comment')
      end
      provider.create(context, 'm', should)
    end
  end

  describe '#update' do
    it 'puts to /config/notifications/matchers/{name}' do
      should = { name: 'biz-hours', target: ['smtp-relay'], ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/config/notifications/matchers/biz-hours')
      end
      provider.update(context, 'biz-hours', should)
    end

    it 'excludes name and ensure from the PUT body' do
      should = { name: 'biz-hours', target: ['smtp-relay'], ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('name')
        expect(body).not_to have_key('ensure')
      end
      provider.update(context, 'biz-hours', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /config/notifications/matchers/{name}' do
      expect(mock_transport).to receive(:delete).with(context, '/config/notifications/matchers/biz-hours')
      provider.delete(context, 'biz-hours')
    end
  end
end
