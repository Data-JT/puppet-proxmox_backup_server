# frozen_string_literal: true

require 'spec_helper'
require 'etc'
require 'json'
require 'tmpdir'
require 'puppet_x/proxmox_backup_server/shadow_writer'

# No example touches a real /etc/proxmox-backup: every one redirects the store's
# config_dir at a tmpdir.
RSpec.describe PuppetX::ProxmoxBackupServer::ShadowWriter do
  let(:store) { PuppetX::ProxmoxBackupServer::SecretStore }
  let(:directory) { store.config_dir }
  let(:shadow_path) { File.join(directory, 'shadow.json') }

  around(:each) do |example|
    Dir.mktmpdir do |dir|
      store.config_dir = dir
      example.run
      store.config_dir = nil
    end
  end

  # Default to "no backup group", so examples not about ownership take the
  # 0600 fallback instead of attempting a chown this process cannot perform.
  before(:each) do
    allow(Etc).to receive(:getgrnam).with('backup').and_raise(ArgumentError, "can't find group for backup")
  end

  describe '.read' do
    it 'returns the parsed hashes' do
      File.write(shadow_path, '{"john":"$y$hash"}')
      expect(described_class.read).to eq('john' => '$y$hash')
    end

    it 'returns an empty hash when the file does not exist' do
      expect(described_class.read).to eq({})
    end

    it 'raises when the file contains invalid JSON' do
      File.write(shadow_path, '{invalid')
      expect { described_class.read }
        .to raise_error(Puppet::ResourceError, %r{Failed to read .*shadow\.json})
    end
  end

  describe '.set_password' do
    it 'stores a verifiable yescrypt hash under the bare username' do
      described_class.set_password('john@pbs', 'hunter2')
      stored = described_class.read
      expect(stored.keys).to eq(['john'])
      expect(PuppetX::ProxmoxBackupServer::Crypt.verify('hunter2', stored['john'])).to be true
    end

    it 'never stores the plaintext' do
      described_class.set_password('john@pbs', 'hunter2')
      expect(File.read(shadow_path)).not_to include('hunter2')
    end

    it 'leaves other users untouched' do
      File.write(shadow_path, '{"other":"$y$existing"}')
      described_class.set_password('john@pbs', 'hunter2')
      expect(described_class.read['other']).to eq('$y$existing')
    end

    it 'replaces an existing hash for the same user' do
      described_class.set_password('john@pbs', 'first')
      first = described_class.read['john']
      described_class.set_password('john@pbs', 'second')
      expect(described_class.read['john']).not_to eq(first)
    end
  end

  describe '.remove_password' do
    it 'removes the hash stored under the bare username' do
      File.write(shadow_path, '{"john":"$y$hash","other":"$y$existing"}')
      expect(described_class.remove_password('john@pbs')).to be true
      expect(described_class.read).to eq('other' => '$y$existing')
    end

    # Rewriting an unchanged file would still replace its inode and mint a
    # change, so absence must be a true no-op.
    it 'returns false and leaves the file untouched when the user has no hash' do
      File.write(shadow_path, '{"other":"$y$existing"}')
      original_inode = File.stat(shadow_path).ino
      expect(described_class.remove_password('john@pbs')).to be false
      expect(File.stat(shadow_path).ino).to eq(original_inode)
    end

    it 'returns false when the shadow file does not exist' do
      expect(described_class.remove_password('john@pbs')).to be false
      expect(File.exist?(shadow_path)).to be false
    end

    it 'preserves the mode of the shadow file' do
      File.write(shadow_path, '{"john":"$y$hash"}')
      File.chmod(0o600, shadow_path)
      described_class.remove_password('john@pbs')
      expect(File.stat(shadow_path).mode & 0o777).to eq(0o600)
    end
  end

  describe 'file ownership' do
    it 'creates a missing shadow file with mode 0600 when the backup group does not exist' do
      allow(Etc).to receive(:getgrnam).with('backup').and_raise(ArgumentError, "can't find group for backup")
      described_class.set_password('john@pbs', 'hunter2')
      expect(File.stat(shadow_path).mode & 0o777).to eq(0o600)
    end

    it 'creates a missing shadow file with group backup and mode 0640 when the group exists' do
      # Use the current process gid so chgrp succeeds without root.
      allow(Etc).to receive(:getgrnam).with('backup').and_return(instance_double(Etc::Group, gid: Process.gid))
      described_class.set_password('john@pbs', 'hunter2')
      expect(File.stat(shadow_path).mode & 0o777).to eq(0o640)
      expect(File.stat(shadow_path).gid).to eq(Process.gid)
    end

    it 'preserves the mode of an existing shadow file' do
      File.write(shadow_path, '{}')
      File.chmod(0o640, shadow_path)
      described_class.set_password('john@pbs', 'hunter2')
      expect(File.stat(shadow_path).mode & 0o777).to eq(0o640)
    end

    # Written via a temporary file and renamed, so a crash cannot leave
    # shadow.json truncated and lock every user out.
    it 'replaces the file atomically and leaves no temporary file behind' do
      File.write(shadow_path, '{}')
      original_inode = File.stat(shadow_path).ino
      described_class.set_password('john@pbs', 'hunter2')
      expect(File.stat(shadow_path).ino).not_to eq(original_inode)
      expect(Dir.children(directory)).to contain_exactly('shadow.json', 'shadow.json.lock')
    end
  end
end
