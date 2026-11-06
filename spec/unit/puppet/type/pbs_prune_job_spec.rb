# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_prune_job'

RSpec.describe 'pbs_prune_job type' do
  let(:type) { Puppet::Type.type(:pbs_prune_job) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :id as the namevar' do
    expect(type.key_attributes).to include(:id)
  end

  describe 'id validation' do
    it 'accepts a safe-ID job ID' do
      expect { type.new(id: 'prune-backup1_daily.01', store: 'backup1', job_schedule: 'daily') }.not_to raise_error
    end

    it 'rejects an ID containing a slash' do
      expect { type.new(id: 'evil/../job', store: 'backup1', job_schedule: 'daily') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects an ID containing whitespace' do
      expect { type.new(id: 'bad job', store: 'backup1', job_schedule: 'daily') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(id: 'prune1', store: 'backup1', job_schedule: 'daily', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(id: 'prune1', store: 'backup1', job_schedule: 'daily', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        id:           'prune-backup1',
        store:        'backup1',
        job_schedule: 'daily',
        ns:           'production',
        keep_last:    3,
        keep_hourly:  24,
        keep_daily:   7,
        keep_weekly:  4,
        keep_monthly: 12,
        keep_yearly:  2,
        comment:      'standard retention',
      )
    end

    it { expect(resource[:id]).to eq('prune-backup1') }
    it { expect(resource[:store]).to eq('backup1') }
    it { expect(resource[:job_schedule]).to eq('daily') }
    it { expect(resource[:ns]).to eq('production') }
    it { expect(resource[:keep_last]).to eq(3) }
    it { expect(resource[:keep_hourly]).to eq(24) }
    it { expect(resource[:keep_daily]).to eq(7) }
    it { expect(resource[:keep_weekly]).to eq(4) }
    it { expect(resource[:keep_monthly]).to eq(12) }
    it { expect(resource[:keep_yearly]).to eq(2) }
    it { expect(resource[:comment]).to eq('standard retention') }
  end

  describe 'keep_* attributes' do
    it 'rejects a non-integer keep_daily' do
      expect { type.new(id: 'prune1', store: 'backup1', job_schedule: 'daily', keep_daily: 'many') }
        .to raise_error(Puppet::ResourceError)
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(id: 'prune1', store: 'backup1', job_schedule: 'daily') }

    [:ns, :keep_last, :keep_hourly, :keep_daily, :keep_weekly, :keep_monthly, :keep_yearly, :comment].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end
end
