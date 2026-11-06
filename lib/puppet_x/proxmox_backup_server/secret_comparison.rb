# frozen_string_literal: true

require 'puppet'
require_relative 'secret_store'

# @api private
module PuppetX; end
# @api private
module PuppetX::ProxmoxBackupServer; end

# Drift detection and enforcement for the secrets PBS never returns.
#
# Mixed into Puppet::Provider::PbsBaseProvider rather than defined there, so
# the provider keeps its API-mapping responsibility and this keeps its
# comparison one. Providers that own secrets declare `self.secret_attributes`
# and implement `stored_secret`.
#
# The Resource API only calls insync? when the type declares
# `features: ['custom_insync']`; without it the hook is defined but never wired
# up (resource_api/property.rb:28) and every secret silently falls back to the
# default comparison.
#
# ALWAYS require this file with `require_relative`: a module's lib/ is never on
# $LOAD_PATH inside puppetserver, so a bare require breaks type autoloading.
#
# The nil-checks below distinguish "PBS holds no secret" from "the value is
# absent from the catalog", which are different answers; collapsing them would
# reintroduce the silent no-op this code removes.
module PuppetX::ProxmoxBackupServer::SecretComparison
  SecretStore = PuppetX::ProxmoxBackupServer::SecretStore

  # Reported as the `is` value for a secret the store holds. Deliberately a
  # constant: a placeholder that varied between runs would itself be drift.
  SECRET_PLACEHOLDER = '[secret managed]'

  # Returning nil is the Resource API insync? contract: it signals "I do not
  # handle this property, fall back to the default comparison" -- not a boolean
  # predicate, so nil must not be collapsed to false.
  #
  # The second return value replaces Puppet's "changed X to Y" notice text.
  def insync?(_context, _title, attribute_name, _is, should)
    return nil unless self.class.secret_attributes.include?(attribute_name) # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

    return true unless secret_drifted?(attribute_name, should)

    [false, "#{attribute_name} changed"]
  end

  # Update body with every already-matching secret removed.
  #
  # PBS preserves a secret that a PUT omits (verified on 4.2.1), so dropping
  # in-sync secrets keeps an unchanged credential out of the request entirely.
  # Resending it unconditionally is what made every run rewrite the stored
  # value and mint a change event -- the bug this mechanism exists to remove.
  def update_body(context, should)
    request_body(context, without_unchanged_secrets(should), for_update: true)
  end

  def without_unchanged_secrets(should)
    unchanged = self.class.secret_attributes.reject { |attribute| secret_drifted?(attribute, should) }
    should.reject { |key, _| unchanged.include?(key) }
  end

  # A secret is in sync when the copy PBS persists on the node matches the
  # declared one.
  #
  # Fails closed: if the store cannot be read we raise rather than assume a
  # match. A false "in sync" here would silently disable enforcement, which is
  # the failure mode this whole mechanism exists to remove.
  #
  # An undeclared secret never drifts -- Puppet is not managing it, so whatever
  # PBS holds is by definition correct.
  def secret_drifted?(attribute_name, should)
    desired = unwrap_secret(should[attribute_name])
    return false if desired.nil?

    SecretStore.assert_available!(attribute_name)
    stored = stored_secret(attribute_name, should)
    stored.nil? || !secret_matches?(attribute_name, stored, desired)
  end

  # The `is` value to report for a declared secret: a constant placeholder when
  # PBS holds one, and the key omitted entirely when it does not. Never the
  # secret itself -- insync? intercepts before the value is ever compared.
  #
  # Returns nothing when the store is unreadable, because get() runs during
  # discovery for every resource in the catalog, including ones managing no
  # secrets at all, and so must never raise merely because the agent is not on
  # a PBS node. The fail-closed assertion lives in secret_drifted?, which only
  # runs for attributes actually declared.
  def secret_placeholders(current)
    return {} unless SecretStore.available?

    self.class.secret_attributes.each_with_object({}) do |attribute, result|
      stored = stored_secret(attribute, current)
      result[attribute] = secret_placeholder(attribute, stored) unless stored.nil?
    end
  end

  # Overridden where the attribute's declared type is not a String.
  def secret_placeholder(_attribute_name, _stored)
    SECRET_PLACEHOLDER
  end

  def stored_secret(_attribute_name, _should)
    raise NotImplementedError,
          "#{self.class} declares secret_attributes but does not implement stored_secret"
  end

  # Plaintext against plaintext by default, which covers four of the seven
  # secrets. pbs_user overrides this to verify against a crypt(3) hash, and
  # pbs_notification_target to compare the webhook secret set.
  def secret_matches?(_attribute_name, stored, desired)
    stored == desired
  end

  # Hiera/eyaml lookups yield a plain String; a Sensitive() declaration and the
  # Resource API's own re-wrapping both yield something with #unwrap.
  def unwrap_secret(value)
    return nil if value.nil?

    value.respond_to?(:unwrap) ? value.unwrap : value
  end
end
