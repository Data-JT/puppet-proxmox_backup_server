# frozen_string_literal: true

require 'etc'
require 'json'
require 'puppet'
require 'tempfile'
require_relative 'crypt'
require_relative 'secret_store'

# @api private
module PuppetX; end
# @api private
module PuppetX::ProxmoxBackupServer; end

# Writes password hashes into /etc/proxmox-backup/shadow.json.
#
# The counterpart to SecretStore, which reads it. Kept separate from the
# provider so that provider stays about the PBS API, and separate from the
# store so that the store stays strictly read-only.
#
# This exists because no remote path can set a PBS password. The API's
# PUT /access/password requires confirmation-password -- the user's *current*
# password -- unless authenticated as root@pam, and that is exactly what is
# unknown once the password has drifted. `proxmox-backup-manager user update
# --password` is documented as ignored, and every PBS CLI takes secrets on
# argv where any local user could read them from ps.
#
# ALWAYS require this file with `require_relative`: a module's lib/ is never on
# $LOAD_PATH inside puppetserver, so a bare require breaks type autoloading.
module PuppetX::ProxmoxBackupServer::ShadowWriter
  SHADOW_FILE = 'shadow.json'
  LOCK_FILE = 'shadow.json.lock'
  # PBS keeps its configs root:backup 0640.
  PBS_GROUP = 'backup'
  PBS_MODE = 0o640
  # Used when the backup group does not exist, e.g. on a non-PBS test host.
  FALLBACK_MODE = 0o600

  class << self
    def path
      File.join(PuppetX::ProxmoxBackupServer::SecretStore.config_dir, SHADOW_FILE)
    end

    def lock_path
      File.join(PuppetX::ProxmoxBackupServer::SecretStore.config_dir, LOCK_FILE)
    end

    # Hashes plaintext with a fresh yescrypt salt and stores it under the bare
    # username, taking the same lock file PBS itself uses.
    def set_password(userid, plaintext)
      username = userid.to_s.split('@').first
      hash = PuppetX::ProxmoxBackupServer::Crypt.generate_hash(plaintext)

      with_lock { write(read.merge(username => hash)) }
    end

    # Removes the user's hash, which is the only way to stop a @pbs user
    # logging in with a password while keeping the user (and so its API
    # tokens). Returns whether there was a hash to remove; when there was not,
    # the file is not rewritten.
    def remove_password(userid)
      username = userid.to_s.split('@').first
      with_lock { remove_entry(username) }
    end

    def read
      JSON.parse(File.read(path))
    rescue Errno::ENOENT
      {}
    rescue JSON::ParserError, SystemCallError => error
      raise Puppet::ResourceError, "Failed to read #{path}: #{error.message}"
    end

    private

    # Holds the lock file PBS itself uses around a read-modify-write of
    # shadow.json and returns the block's value.
    def with_lock
      File.open(lock_path, File::CREAT | File::RDWR) do |lock|
        lock.flock(File::LOCK_EX)
        yield
      end
    end

    # Must run under with_lock. Leaves the file untouched when there is no
    # entry to remove.
    def remove_entry(username)
      shadow = read
      return false unless shadow.key?(username)

      write(shadow.except(username))
      true
    end

    # Written to a temporary file and renamed, so a crashed run can never
    # leave shadow.json truncated and lock every user out.
    def write(shadow)
      replace(path, JSON.pretty_generate(shadow))
    end

    def replace(target, contents)
      Tempfile.create([SHADOW_FILE, '.tmp'], File.dirname(target)) { |tempfile| persist(tempfile, contents, target) }
    rescue SystemCallError => error
      raise Puppet::ResourceError, "Failed to write #{target}: #{error.message}"
    end

    # fsync before the rename, so a crash cannot leave an empty file where the
    # hashes used to be.
    def persist(tempfile, contents, target)
      apply_ownership(tempfile)
      tempfile.write(contents)
      tempfile.flush
      tempfile.fsync
      tempfile.close
      File.rename(tempfile.path, target)
    end

    def apply_ownership(tempfile)
      uid, gid, mode = ownership
      tempfile.chown(uid, gid)
      tempfile.chmod(mode)
    end

    # Preserve an existing file's ownership and mode; otherwise match what PBS
    # would have created.
    def ownership
      existing = stat
      return [existing.uid, existing.gid, existing.mode & 0o7777] if existing

      gid = group_gid
      return [nil, nil, FALLBACK_MODE] unless gid

      [nil, gid, PBS_MODE]
    end

    def stat
      File.stat(path)
    rescue Errno::ENOENT
      nil
    end

    def group_gid
      Etc.getgrnam(PBS_GROUP).gid
    rescue ArgumentError
      nil
    end
  end
end
