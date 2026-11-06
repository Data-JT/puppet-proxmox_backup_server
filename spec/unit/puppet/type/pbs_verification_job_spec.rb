# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_verification_job'

RSpec.describe 'pbs_verification_job type' do
  let(:type) { Puppet::Type.type(:pbs_verification_job) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :id as the namevar' do
    expect(type.key_attributes).to include(:id)
  end

  describe 'id validation' do
    it 'accepts a safe-ID job ID' do
      expect { type.new(id: 'verify-backup1_weekly.01', store: 'backup1') }.not_to raise_error
    end

    it 'rejects an ID containing a slash' do
      expect { type.new(id: 'evil/../job', store: 'backup1') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects an ID containing whitespace' do
      expect { type.new(id: 'bad job', store: 'backup1') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(id: 'verify1', store: 'backup1', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(id: 'verify1', store: 'backup1', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        id:              'verify-backup1',
        store:           'backup1',
        job_schedule:    'sat 02:00',
        outdated_after:  30,
        ignore_verified: true,
        comment:         'weekly verification',
      )
    end

    it { expect(resource[:id]).to eq('verify-backup1') }
    it { expect(resource[:store]).to eq('backup1') }
    it { expect(resource[:job_schedule]).to eq('sat 02:00') }
    it { expect(resource[:outdated_after]).to eq(30) }
    it { expect(resource[:ignore_verified]).to eq(:true) }
    it { expect(resource[:comment]).to eq('weekly verification') }
  end

  describe 'ignore_verified attribute' do
    it 'defaults to false' do
      resource = type.new(id: 'verify1', store: 'backup1')
      expect(resource[:ignore_verified]).to eq(:false)
    end

    it 'rejects a non-boolean value' do
      expect { type.new(id: 'verify1', store: 'backup1', ignore_verified: 'maybe') }
        .to raise_error(Puppet::ResourceError)
    end
  end

  describe 'outdated_after attribute' do
    it 'rejects a non-integer value' do
      expect { type.new(id: 'verify1', store: 'backup1', outdated_after: 'soon') }
        .to raise_error(Puppet::ResourceError)
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(id: 'verify1', store: 'backup1') }

    [:job_schedule, :outdated_after, :comment].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end
end
