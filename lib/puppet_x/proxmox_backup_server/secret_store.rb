# frozen_string_literal: true

require 'base64'
require 'json'
require 'puppet'

# @api private
module PuppetX; end
# @api private
module PuppetX::ProxmoxBackupServer; end

# Read-only reader for the secrets PBS persists under /etc/proxmox-backup.
#
# The PBS API is write-only for these values -- GET omits them entirely, and
# for a webhook target it returns the secret's name with the value stripped --
# but PBS writes every one of them to the node, none of them encrypted. Reading
# them here is what makes drift detection possible at all.
#
# Verified against PBS 4.2.1:
#
#   ldap_passwords.json     {realm: plaintext}                 0600 root:root
#   remote.cfg              password <base64>                  0640 root:backup
#   s3.cfg                  secret-key <plaintext>             0640 root:backup
#   notifications-priv.cfg  password/token/secret <...>        0600 root:root
#   shadow.json             {username: yescrypt hash}          0600 root:root
#
# Two failure modes, deliberately distinguished:
#
#   * a missing secret *file* means PBS holds no secret       -> nil
#   * an unreadable config *dir* means we cannot know         -> raise
#
# Reporting "in sync" when the value cannot be seen would silently disable
# enforcement, which is the exact bug this module exists to fix. So the second
# case fails closed.
#
# ALWAYS require this file with `require_relative`: a module's lib/ is never on
# $LOAD_PATH inside puppetserver, so a bare require breaks type autoloading.
#
# config_dir is writable purely as a test seam, so specs can point the store at
# a fixture tree instead of a real /etc/proxmox-backup.
module PuppetX::ProxmoxBackupServer::SecretStore
  DEFAULT_CONFIG_DIR = '/etc/proxmox-backup'
  # PBS object names never contain a path separator. Anything that does is a
  # traversal attempt or a bug, and must not reach File.read.
  SAFE_NAME = %r{\A[^/\\\0]+\z}

  class << self
    attr_writer :config_dir

    def config_dir
      @config_dir || DEFAULT_CONFIG_DIR
    end

    # Non-raising probe. get() runs during discovery for every resource in the
    # catalog, including ones managing no secrets at all, so it must never
    # raise merely because the agent is not on a PBS node.
    def available?
      File.directory?(config_dir) && File.readable?(config_dir)
    end

    # Fail-closed guard, called from insync? and therefore only for attributes
    # actually being managed.
    def assert_available!(attribute_name)
      return if available?

      raise Puppet::ResourceError,
            "Cannot verify '#{attribute_name}': #{config_dir} is not readable. " \
            'Managing PBS secrets requires the Puppet agent to run on the PBS node as root.'
    end

    # Both ldap and ad realms share this file, keyed by the full realm name.
    # openid realms are absent from it: PBS returns client-key over the API, so
    # that attribute needs no store at all.
    def realm_password(realm)
      json_file(File.join(config_dir, 'ldap_passwords.json'))[safe(realm)]
    end

    # PBS stores the remote password base64-encoded. That is encoding, not
    # encryption -- but it still has to be decoded before comparison.
    def remote_password(name)
      encoded = section_field(File.join(config_dir, 'remote.cfg'), 'remote', name, 'password')
      return nil if encoded.nil?

      decoded_value(encoded)
    end

    def s3_secret_key(id)
      section_field(File.join(config_dir, 's3.cfg'), 's3-endpoint', id, 'secret-key')
    end

    # smtp -> password, gotify -> token, webhook -> secret. The webhook secret
    # repeats once per entry, so every match is returned.
    def notification_secrets(type, name, field)
      section_fields(File.join(config_dir, 'notifications-priv.cfg'), type, name, field)
    end

    # shadow.json is keyed by the BARE username with the realm stripped, and
    # PBS only consults it for the built-in @pbs realm.
    def user_password_hash(userid)
      username = userid.to_s.split('@').first.to_s
      return nil if username.empty?

      json_file(File.join(config_dir, 'shadow.json'))[username]
    end

    # Whether shadow.json holds a hash for the user, i.e. a password login exists.
    def user_password?(userid)
      !user_password_hash(userid).nil?
    end

    private

    def safe(name)
      value = name.to_s
      return value if SAFE_NAME.match?(value)

      raise Puppet::ResourceError, "invalid PBS object name: #{value.inspect}"
    end

    # nil means "PBS holds no secret here". A read error that is not ENOENT
    # (EACCES on a non-root agent) must not be mistaken for that, so it raises.
    def read_file(path)
      File.read(path)
    rescue Errno::ENOENT
      nil
    rescue SystemCallError => error
      raise Puppet::ResourceError, "Failed to read #{path}: #{error.message}"
    end

    def json_file(path)
      contents = read_file(path).to_s
      return {} if contents.strip.empty?

      parse_hash(contents, path)
    end

    def parse_hash(contents, path)
      parsed = JSON.parse(contents)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError => error
      raise Puppet::ResourceError, "Failed to parse #{path}: #{error.message}"
    end

    # A base64 value PBS wrote should always decode; if it does not, the store
    # is corrupt and reporting a match would be worse than reporting drift.
    def decoded_value(value)
      Base64.strict_decode64(value)
    rescue ArgumentError
      nil
    end

    def section_field(path, type, name, field)
      section_fields(path, type, name, field).first
    end

    # PBS section-config: a "<type>: <name>" header followed by indented
    # "<field> <value>" lines. remote.cfg, s3.cfg and notifications-priv.cfg
    # all use this identical format.
    def section_fields(path, type, name, field)
      contents = read_file(path)
      return [] if contents.nil?

      sections(contents).fetch("#{type}: #{safe(name)}", []).filter_map { |line| field_value(line, field) }
    end

    def field_value(line, field)
      entry, value = line.strip.split(' ', 2)
      value if entry == field.to_s && !value.nil?
    end

    # Splits section-config into {header => [indented lines]}. An unindented
    # line opens a section; indented lines belong to the one above.
    def sections(contents)
      header = nil
      contents.each_line.with_object({}) do |line, result|
        if line.match?(%r{\A\S})
          header = line.strip
        elsif header
          (result[header] ||= []) << line
        end
      end
    end
  end
end
