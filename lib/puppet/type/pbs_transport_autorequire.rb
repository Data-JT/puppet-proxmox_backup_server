# frozen_string_literal: true

# Registers the managed PBS transport file as an automatic dependency.
module Puppet::Type::PbsTransportAutorequire
  def self.register(type_name)
    Puppet::Type.type(type_name).autorequire(:file) do
      File.join(Puppet.settings[:confdir], 'pbs_transport.yaml')
    end
  end
end
