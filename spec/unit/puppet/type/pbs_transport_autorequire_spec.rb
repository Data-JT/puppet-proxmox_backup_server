# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pbs_transport_autorequire'

RSpec.describe Puppet::Type::PbsTransportAutorequire do
  let(:type_name) { :pbs_transport_autorequire_test }

  before(:each) do
    Puppet::Type.newtype(type_name) do
      newparam(:name, namevar: true)
    end
  end

  after(:each) { Puppet::Type.rmtype(type_name) }

  it 'registers an automatic file dependency on the managed transport config path' do
    described_class.register(type_name)

    block = nil
    Puppet::Type.type(type_name).eachautorequire { |dependency_type, registered_block| block = registered_block if dependency_type == :file }

    expect(block).not_to be_nil
    expect(block.call).to eq(File.join(Puppet.settings[:confdir], 'pbs_transport.yaml'))
  end
end
