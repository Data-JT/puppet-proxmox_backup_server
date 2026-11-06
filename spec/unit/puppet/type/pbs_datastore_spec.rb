# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_datastore'

RSpec.describe 'pbs_datastore type' do
  let(:type) { Puppet::Type.type(:pbs_datastore) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :name as the namevar' do
    expect(type.key_attributes).to include(:name)
  end

  describe 'name namevar validation' do
    it 'accepts a PBS safe-ID' do
      expect { type.new(name: 'store_1.a-b', path: '/mnt/backup') }.not_to raise_error
    end

    it 'rejects a name with a slash (URL path injection)' do
      expect { type.new(name: 'bad/../store', path: '/mnt/backup') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a name with whitespace' do
      expect { type.new(name: 'bad store', path: '/mnt/backup') }.to raise_error(Puppet::ResourceError)
    end

    it 'rejects a name longer than 32 characters' do
      expect { type.new(name: 'a' * 33, path: '/mnt/backup') }.to raise_error(Puppet::ResourceError)
    end

    it 'accepts a name of exactly 32 characters' do
      expect { type.new(name: 'a' * 32, path: '/mnt/backup') }.not_to raise_error
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(name: 'mystore', path: '/mnt/backup', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(name: 'mystore', path: '/mnt/backup', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'required attributes' do
    it 'accepts a name and path' do
      expect { type.new(name: 'mystore', path: '/mnt/backup') }.not_to raise_error
    end
  end

  describe 'optional attributes' do
    subject(:resource) { type.new(name: 'mystore', path: '/mnt/backup') }

    [:comment, :gc_schedule].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        name:         'mystore',
        path:         '/mnt/backup',
        comment:      'main store',
        gc_schedule:  'daily',
      )
    end

    it { expect(resource[:name]).to eq('mystore') }
    it { expect(resource[:path]).to eq('/mnt/backup') }
    it { expect(resource[:comment]).to eq('main store') }
    it { expect(resource[:gc_schedule]).to eq('daily') }
  end
end
