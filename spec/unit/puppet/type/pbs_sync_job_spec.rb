# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_sync_job'

RSpec.describe 'pbs_sync_job type' do
  let(:type) { Puppet::Type.type(:pbs_sync_job) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :id as the namevar' do
    expect(type.key_attributes).to include(:id)
  end

  describe 'id namevar validation' do
    it 'accepts a PBS safe-ID' do
      expect { type.new(id: 'daily_sync-1.a', store: 'local', remote_store: 'offsite') }.not_to raise_error
    end

    it 'rejects an id with a slash (URL path injection)' do
      expect { type.new(id: 'bad/../id', store: 'local', remote_store: 'offsite') }
        .to raise_error(Puppet::ResourceError)
    end

    it 'rejects an id with whitespace' do
      expect { type.new(id: 'bad id', store: 'local', remote_store: 'offsite') }
        .to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'remove_vanished attribute' do
    it 'defaults to false' do
      resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite')
      expect(resource[:remove_vanished]).to eq(:false)
    end

    it 'accepts true' do
      resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite', remove_vanished: true)
      expect(resource[:remove_vanished]).to eq(:true)
    end
  end

  describe 'sync_direction attribute' do
    ['pull', 'push'].each do |dir|
      it "accepts #{dir}" do
        expect { type.new(id: 'j1', store: 'local', remote_store: 'offsite', sync_direction: dir) }.not_to raise_error
      end
    end

    it 'rejects an unknown direction' do
      expect { type.new(id: 'j1', store: 'local', remote_store: 'offsite', sync_direction: 'copy') }.to raise_error(Puppet::ResourceError)
    end

    it 'is nil when not set' do
      resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite')
      expect(resource[:sync_direction]).to be_nil
    end
  end

  describe 'optional integer attributes' do
    [:max_depth, :transfer_last, :worker_threads].each do |attr|
      it "#{attr} is nil when not set" do
        resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite')
        expect(resource[attr]).to be_nil
      end

      it "#{attr} accepts an integer" do
        expect { type.new(id: 'j1', store: 'local', remote_store: 'offsite', attr => 4) }.not_to raise_error
      end
    end
  end

  describe 'optional boolean attributes' do
    [:resync_corrupt, :encrypted_only, :verified_only].each do |attr|
      it "#{attr} is nil when not set" do
        resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite')
        expect(resource[attr]).to be_nil
      end

      it "#{attr} accepts true" do
        resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite', attr => true)
        expect(resource[attr]).to eq(:true)
      end

      it "#{attr} accepts false" do
        resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite', attr => false)
        expect(resource[attr]).to eq(:false)
      end
    end
  end

  describe 'group_filter attribute' do
    it 'is nil when not set' do
      resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite')
      expect(resource[:group_filter]).to be_nil
    end

    it 'accepts an array of filter expressions' do
      resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite', group_filter: ['type:vm', 'group:vm/100'])
      expect(resource[:group_filter]).to eq(['type:vm', 'group:vm/100'])
    end

    it 'rejects a bare string (the PBS API field is an array)' do
      expect { type.new(id: 'j1', store: 'local', remote_store: 'offsite', group_filter: 'type:vm') }
        .to raise_error(Puppet::ResourceError)
    end
  end

  describe 'optional string attributes' do
    [:remote, :remote_ns, :ns, :owner, :job_schedule, :comment].each do |attr|
      it "#{attr} is nil when not set" do
        resource = type.new(id: 'j1', store: 'local', remote_store: 'offsite')
        expect(resource[attr]).to be_nil
      end
    end
  end

  describe 'all attributes settable' do
    subject(:resource) do
      type.new(
        id:              'full-sync',
        store:           'local',
        remote:          'offsite',
        remote_store:    'backup',
        remote_ns:       'vm/100',
        ns:              'imported',
        max_depth:       2,
        sync_direction:  'pull',
        owner:           'puppet@pbs',
        group_filter:    ['type:vm', 'group:vm/100'],
        job_schedule:    'daily',
        remove_vanished: false,
        transfer_last:   3,
        resync_corrupt:  true,
        encrypted_only:  false,
        verified_only:   false,
        worker_threads:  4,
        comment:         'full sync job',
      )
    end

    it { expect(resource[:id]).to eq('full-sync') }
    it { expect(resource[:store]).to eq('local') }
    it { expect(resource[:remote]).to eq('offsite') }
    it { expect(resource[:remote_store]).to eq('backup') }
    it { expect(resource[:remote_ns]).to eq('vm/100') }
    it { expect(resource[:ns]).to eq('imported') }
    it { expect(resource[:max_depth]).to eq(2) }
    it { expect(resource[:sync_direction]).to eq('pull') }
    it { expect(resource[:owner]).to eq('puppet@pbs') }
    it { expect(resource[:group_filter]).to eq(['type:vm', 'group:vm/100']) }
    it { expect(resource[:job_schedule]).to eq('daily') }
    it { expect(resource[:remove_vanished]).to eq(:false) }
    it { expect(resource[:transfer_last]).to eq(3) }
    it { expect(resource[:resync_corrupt]).to eq(:true) }
    it { expect(resource[:worker_threads]).to eq(4) }
    it { expect(resource[:comment]).to eq('full sync job') }
  end
end
