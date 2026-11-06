# frozen_string_literal: true

require_relative '../pbs_base_provider'
require_relative '../../../puppet_x/proxmox_backup_server/crypt'
require_relative '../../../puppet_x/proxmox_backup_server/shadow_writer'

# @api private
module Puppet::Provider::PbsUser; end

# Provider for pbs_user resources via the PBS REST API and shadow.json.
#
# Password management is only supported for @pbs realm users and requires the
# Puppet agent to run on the PBS host itself: hashes are verified against and
# written to the local /etc/proxmox-backup/shadow.json.
#
# The API cannot do this. PUT /access/password requires confirmation-password
# -- the user's *current* password -- unless authenticated as root@pam, and the
# current password is precisely what is unknown once it has drifted. The
# proxmox-backup-manager CLI is no help either: `user update --password` is
# documented as ignored, and every PBS CLI takes secrets on argv, where any
# local user could read them from ps.
class Puppet::Provider::PbsUser::ProxmoxBackupServer < Puppet::Provider::PbsBaseProvider
  Crypt = PuppetX::ProxmoxBackupServer::Crypt
  ShadowWriter = PuppetX::ProxmoxBackupServer::ShadowWriter

  # validate_password_login! check for each declared password_login value.
  PASSWORD_LOGIN_CHECKS = {
    true => :require_login_password!,
    false => :reject_declared_password!,
  }.freeze

  def self.attribute_map
    {
      'userid'     => :userid,
      'comment'    => :comment,
      'email'      => :email,
      'enable'     => :enable,
      'expire'     => :expire,
      'firstname'  => :firstname,
      'lastname'   => :lastname,
      'delete'     => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:enable]
  end

  def self.secret_attributes
    [:password]
  end

  # shadow.json only holds passwords for the built-in @pbs realm; other realms
  # (pam, ldap, ...) authenticate elsewhere and must never match.
  def stored_secret(_attribute_name, current)
    userid = current[:userid]
    return nil unless pbs_realm_userid?(userid)

    SecretStore.user_password_hash(userid)
  end

  # The stored value is a crypt(3) hash, not the password, so this is a
  # verification rather than a comparison. Passing the stored hash back as the
  # setting keeps it scheme-agnostic.
  def secret_matches?(_attribute_name, stored, desired)
    Crypt.verify(desired, stored)
  end

  def get(context)
    (transport_get(context, '/access/users') || []).map do |user|
      puppet_user = pbs_to_puppet(user).merge(ensure: 'present')
      # PBS omits 'enable' from the response when the user is enabled (implicit default).
      puppet_user[:enable] = true unless puppet_user.key?(:enable)
      puppet_user.merge(secret_placeholders(puppet_user)).merge(password_login_state(puppet_user))
    end
  end

  def create(context, name, should)
    validate_userid!(name)
    validate_password_login!(name, should)
    context.notice("Creating user '#{name}'")
    body = request_body(context, should)
    if (pw = should[:password])
      validate_password_realm!(name)
      body['password'] = unwrap_secret(pw)
    end
    pbs_transport(context).post(context, '/access/users', body)
  end

  def update(context, name, should)
    validate_userid!(name)
    validate_password_login!(name, should)
    context.notice("Updating user '#{name}'")
    pbs_transport(context).put(context, "/access/users/#{name}", request_body(context, should, for_update: true))
    if to_bool(should[:password_login]) == false
      context.notice("Removing the password of '#{name}' from shadow.json") if ShadowWriter.remove_password(name)
      return
    end

    password = should[:password]
    return unless password

    validate_password_realm!(name)
    # Checked before writing: rewriting an identical hash would mint a change
    # event on every run, which is the bug this mechanism exists to remove.
    ShadowWriter.set_password(name, unwrap_secret(password)) if secret_drifted?(:password, should)
  end

  def delete(context, name)
    context.notice("Deleting user '#{name}'")
    pbs_transport(context).delete(context, "/access/users/#{name}")
  end

  private

  def validate_userid!(userid)
    return if userid.match?(%r{\A[^@\s]+@[^@\s]+\z})

    raise Puppet::ResourceError, "userid must be in user@realm format, got: #{userid.inspect}"
  end

  # Whether a password login exists at all, i.e. shadow.json holds a hash.
  # Reported only where it can be known: @pbs realm users, on the PBS node.
  def password_login_state(current)
    userid = current[:userid]
    return {} unless pbs_realm_userid?(userid) && SecretStore.available?

    { password_login: SecretStore.user_password?(userid) }
  end

  # Raised before any API call, so a contradictory declaration changes nothing.
  # password_login is Optional[Boolean]; unset leaves it unmanaged and has no
  # entry here.
  def validate_password_login!(userid, should)
    check = PASSWORD_LOGIN_CHECKS[to_bool(should[:password_login])]
    return unless check

    validate_password_realm!(userid)
    send(check, userid, should)
  end

  # Nothing can create a login without a value, so true needs a declared or an
  # already stored password.
  def require_login_password!(userid, should)
    return if unwrap_secret(should[:password]) || SecretStore.user_password?(userid)

    raise Puppet::ResourceError, "pbs_user '#{userid}': password_login => true requires a password"
  end

  def reject_declared_password!(userid, should)
    return unless unwrap_secret(should[:password])

    raise Puppet::ResourceError, "pbs_user '#{userid}': password_login => false contradicts a declared password"
  end

  def pbs_realm_userid?(userid)
    userid.to_s.end_with?('@pbs')
  end

  def validate_password_realm!(userid)
    return if pbs_realm_userid?(userid)

    raise Puppet::ResourceError,
          "pbs_user '#{userid}': password management is only supported for @pbs realm users " \
          '(passwords are stored in /etc/proxmox-backup/shadow.json, which PBS only consults for the pbs realm)'
  end
end
