# frozen_string_literal: true

require 'puppet'

# @api private
module PuppetX; end
# @api private
module PuppetX::ProxmoxBackupServer; end

# Checks one Resource API change before the provider sends anything to PBS.
#
# Two kinds of declaration can never converge, so they fail the run here with
# a message naming the Puppet attribute:
#
# * a change to an attribute PBS takes only when the resource is created. The
#   Resource API refuses a change to an init_only attribute by itself, but
#   only while Puppet's `strict` setting is `error` (the default). Under
#   `warning` or `off` it lets the change through, and since the update request
#   leaves the attribute out, the resource would report the same change on
#   every run. This check holds whatever `strict` says.
# * an attribute that does not belong to the resource's `type`, which PBS would
#   refuse only once the request is sent, naming the API key.
class PuppetX::ProxmoxBackupServer::ChangeCheck
  def initialize(name, change)
    @name = name.is_a?(Hash) ? name.values.join('/') : name.to_s
    @is = change[:is] || {}
    @should = change[:should] || {}
  end

  # provider: the provider class. Its attributes_by_type lists the
  # type-specific attributes for each value of `type` (attributes listed for
  # no type apply to all of them), or is nil for a resource without types; its
  # create_only_attributes names the attributes fixed at creation.
  def run(provider, context)
    return unless wanted?

    by_type = provider.attributes_by_type
    refuse_foreign(by_type) if by_type
    refuse_change(provider.create_only_attributes(context, resource)) if existing?
  end

  def wanted?
    @should[:ensure].to_s == 'present'
  end

  def existing?
    @is[:ensure].to_s == 'present'
  end

  # The resource as it will be: current state overlaid with the declaration.
  def resource
    @is.merge(@should)
  end

  def type
    resource[:type].to_s
  end

  private

  def refuse_change(create_only)
    changed = create_only.find { |attribute| @should.key?(attribute) && @should[attribute] != @is[attribute] }
    return unless changed

    raise Puppet::ResourceError,
          "#{@name}: #{changed} cannot be changed from #{@is[changed].inspect} to " \
          "#{@should[changed].inspect}; recreate the resource instead"
  end

  def refuse_foreign(by_type)
    foreign = @should.compact.keys & (by_type.values.flatten - by_type.fetch(type, []))
    return if foreign.empty?

    raise Puppet::ResourceError,
          "#{@name}: #{foreign.join(', ')} #{foreign.one? ? 'does' : 'do'} not apply to type #{type}"
  end
end
