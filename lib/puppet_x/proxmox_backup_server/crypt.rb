# frozen_string_literal: true

require 'fiddle'
require 'puppet'

# @api private
module PuppetX; end
# @api private
module PuppetX::ProxmoxBackupServer; end

# crypt(3) hashing and verification for the password hashes PBS keeps in
# /etc/proxmox-backup/shadow.json.
#
# Verification is deliberately scheme-agnostic: passing the stored hash back to
# crypt(3) as the *setting* makes it re-derive with the same scheme, salt and
# cost. PBS 4.2.1 writes $y$ (yescrypt); the sibling PVE module sees $5$
# (SHA-256 crypt). One call covers both, and survives PBS changing its mind.
#
# ALWAYS require this file with `require_relative`: a module's lib/ is never on
# $LOAD_PATH inside puppetserver, so a bare require breaks type autoloading.
module PuppetX::ProxmoxBackupServer::Crypt
  LIBCRYPT = 'libcrypt.so.1'
  # PBS hashes new passwords with yescrypt; crypt_gensalt picks the cost.
  YESCRYPT_PREFIX = '$y$'
  # crypt(3) signals failure with NULL or a token starting with '*'.
  FAILURE_TOKEN = '*'
  # Generous upper bound for a crypt(3) result; yescrypt hashes are the longest
  # in practice at well under 128 bytes.
  RESULT_LIMIT = 512

  # True when plaintext is the password that produced stored_hash.
  #
  # Never raises on a hash it cannot handle: a corrupt or future-scheme entry
  # reports drift instead of failing the run, so one bad shadow.json entry
  # cannot take down an otherwise healthy catalog.
  def self.verify(plaintext, stored_hash)
    return false if stored_hash.nil? || stored_hash.to_s.empty?

    derived = hash_password(plaintext, stored_hash)
    return false if derived.nil?

    derived == stored_hash
  end

  # Returns the crypt(3) output for plaintext under the given setting, or nil
  # when crypt(3) rejects the setting (unknown scheme, salt too short).
  #
  # Note that crypt(3) accepts a bare alphanumeric string as a legacy DES salt,
  # so "rejected" is narrower than "not a recognisable hash".
  def self.hash_password(plaintext, setting)
    result = crypt_function.call(plaintext.to_s, setting.to_s)
    return nil if result.null?

    derived = result[0, RESULT_LIMIT].split("\x00", 2).first
    return nil if derived.nil? || derived.empty? || derived.start_with?(FAILURE_TOKEN)

    derived
  end

  # Hashes plaintext with a freshly generated yescrypt salt, for writing into
  # shadow.json. Raises rather than returning nil: a caller about to persist a
  # password must never store an unusable hash.
  def self.generate_hash(plaintext)
    derived = hash_password(plaintext, yescrypt_setting)
    raise Puppet::ResourceError, 'crypt(3) rejected the generated yescrypt setting' if derived.nil?

    derived
  end

  def self.yescrypt_setting
    result = crypt_gensalt_function.call(YESCRYPT_PREFIX, 0, nil, 0)
    salt = result.null? ? nil : result[0, RESULT_LIMIT].split("\x00", 2).first
    raise Puppet::ResourceError, 'crypt_gensalt produced no yescrypt setting' if salt.nil? || salt.empty?

    salt
  end
  private_class_method :yescrypt_setting

  def self.crypt_function
    @crypt_function ||= bind('crypt', [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP])
  end
  private_class_method :crypt_function

  def self.crypt_gensalt_function
    @crypt_gensalt_function ||=
      bind('crypt_gensalt', [Fiddle::TYPE_VOIDP, Fiddle::TYPE_LONG, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT])
  end
  private_class_method :crypt_gensalt_function

  # Kept distinct from a load failure: a missing symbol means libcrypt is
  # present but not the libxcrypt PBS relies on, which is a different fix.
  def self.bind(symbol, argument_types)
    Fiddle::Function.new(library[symbol], argument_types, Fiddle::TYPE_VOIDP)
  rescue Fiddle::DLError => error
    raise Puppet::ResourceError, "Failed to bind #{symbol}(3) from #{LIBCRYPT}: #{error.message}"
  end
  private_class_method :bind

  def self.library
    @library ||= Fiddle::Handle.new(LIBCRYPT)
  rescue Fiddle::DLError => error
    raise Puppet::ResourceError, "Failed to load #{LIBCRYPT} for password hashing: #{error.message}"
  end
  private_class_method :library
end
