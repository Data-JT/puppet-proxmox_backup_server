# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_notification_matcher'

RSpec.describe 'pbs_notification_matcher type' do
  let(:type) { Puppet::Type.type(:pbs_notification_matcher) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :name as the namevar' do
    expect(type.key_attributes).to include(:name)
  end

  describe 'name validation' do
    it 'accepts a safe-ID name' do
      expect { type.new(name: 'business-hours_errors.01') }.not_to raise_error
    end

    it 'rejects a name containing a slash' do
      expect { type.new(name: 'evil/../name') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a name containing whitespace' do
      expect { type.new(name: 'bad name') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(name: 'alerts', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(name: 'alerts', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        name:            'business-hours-errors',
        target:          ['smtp-relay', 'gotify'],
        match_severity:  ['error', 'warning'],
        match_calendar:  ['mon-fri 09:00-17:00'],
        match_field:     ['exact:type=gc'],
        mode:            'all',
        invert_match:    false,
        disable:         false,
        comment:         'notify during business hours',
      )
    end

    it { expect(resource[:name]).to eq('business-hours-errors') }
    it { expect(resource[:target]).to eq(['smtp-relay', 'gotify']) }
    it { expect(resource[:match_severity]).to eq(['error', 'warning']) }
    it { expect(resource[:match_calendar]).to eq(['mon-fri 09:00-17:00']) }
    it { expect(resource[:match_field]).to eq(['exact:type=gc']) }
    it { expect(resource[:mode]).to eq('all') }
    it { expect(resource[:invert_match]).to eq(:false) }
    it { expect(resource[:disable]).to eq(:false) }
    it { expect(resource[:comment]).to eq('notify during business hours') }
  end

  describe 'mode attribute' do
    it 'accepts all' do
      expect { type.new(name: 'm', mode: 'all') }.not_to raise_error
    end

    it 'accepts any' do
      expect { type.new(name: 'm', mode: 'any') }.not_to raise_error
    end

    it 'rejects unknown mode' do
      expect { type.new(name: 'm', mode: 'none') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(name: 'empty-matcher') }

    [:target, :match_severity, :match_calendar, :match_field, :mode, :invert_match, :disable, :comment].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end
end
