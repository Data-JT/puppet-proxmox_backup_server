# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'puppet_x/proxmox_backup_server/secret_store'

# Every fixture below reproduces a real file captured from PBS 4.2.1, including
# the tab indentation PBS writes. No example touches /etc/proxmox-backup.
RSpec.describe PuppetX::ProxmoxBackupServer::SecretStore do
  around(:each) do |example|
    Dir.mktmpdir do |dir|
      described_class.config_dir = dir
      example.run
      described_class.config_dir = nil
    end
  end

  let(:config_dir) { described_class.config_dir }

  def write(name, contents)
    File.write(File.join(config_dir, name), contents)
  end

  describe '.available?' do
    it 'is true for a readable directory' do
      expect(described_class).to be_available
    end

    it 'is false when the directory does not exist' do
      described_class.config_dir = File.join(config_dir, 'absent')
      expect(described_class).not_to be_available
    end
  end

  describe '.assert_available!' do
    it 'stays silent when the store is readable' do
      expect { described_class.assert_available!(:password) }.not_to raise_error
    end

    # Fail closed: an unreadable store must never be reported as "in sync".
    it 'raises naming the attribute and the path when it is not' do
      described_class.config_dir = File.join(config_dir, 'absent')
      expect { described_class.assert_available!(:password) }
        .to raise_error(Puppet::ResourceError, %r{Cannot verify 'password'.*is not readable})
    end
  end

  describe '.realm_password' do
    it 'returns the plaintext bind password for an ldap realm' do
      write('ldap_passwords.json', %({\n  "corp-ldap": "SectestLdapAAAA1111"\n}))
      expect(described_class.realm_password('corp-ldap')).to eq('SectestLdapAAAA1111')
    end

    # Verified on PBS 4.2.1: ad realms share ldap_passwords.json with ldap.
    it 'returns the bind password for an ad realm from the same file' do
      write('ldap_passwords.json', %({"corp-ad": "SectestAdHHHH8888"}))
      expect(described_class.realm_password('corp-ad')).to eq('SectestAdHHHH8888')
    end

    it 'returns nil when the realm has no stored password' do
      write('ldap_passwords.json', %({"other": "x"}))
      expect(described_class.realm_password('corp-ldap')).to be_nil
    end

    it 'returns nil when the file does not exist' do
      expect(described_class.realm_password('corp-ldap')).to be_nil
    end

    it 'treats the empty file PBS leaves behind as holding no secrets' do
      write('ldap_passwords.json', '{}')
      expect(described_class.realm_password('corp-ldap')).to be_nil
    end

    it 'raises on a corrupt store rather than reporting no secret' do
      write('ldap_passwords.json', 'not json')
      expect { described_class.realm_password('corp-ldap') }
        .to raise_error(Puppet::ResourceError, %r{Failed to parse})
    end

    it 'rejects a realm name containing a path separator' do
      expect { described_class.realm_password('../../etc/shadow') }
        .to raise_error(Puppet::ResourceError, %r{invalid PBS object name})
    end
  end

  describe '.remote_password' do
    # PBS stores this base64-encoded; the store must hand back plaintext.
    it 'base64-decodes the stored password' do
      write('remote.cfg', "remote: offsite\n\tauth-id sync@pbs\n\thost pbs.example.com\n\tpassword U2VjdGVzdFJlbW90ZUNDQ0MzMzMz\n")
      expect(described_class.remote_password('offsite')).to eq('SectestRemoteCCCC3333')
    end

    it 'returns nil for a remote with no password line' do
      write('remote.cfg', "remote: offsite\n\thost pbs.example.com\n")
      expect(described_class.remote_password('offsite')).to be_nil
    end

    it 'returns nil for a remote that is not in the file' do
      write('remote.cfg', "remote: other\n\tpassword U2VjdGVzdFJlbW90ZUNDQ0MzMzMz\n")
      expect(described_class.remote_password('offsite')).to be_nil
    end

    it 'returns nil when the stored value is not valid base64' do
      write('remote.cfg', "remote: offsite\n\tpassword !!!notbase64!!!\n")
      expect(described_class.remote_password('offsite')).to be_nil
    end

    it 'returns nil when the file is empty, as it is on a fresh PBS' do
      write('remote.cfg', '')
      expect(described_class.remote_password('offsite')).to be_nil
    end
  end

  describe '.s3_secret_key' do
    # Plaintext, unlike remote.cfg -- verified on PBS 4.2.1.
    it 'returns the plaintext secret key' do
      write('s3.cfg', "s3-endpoint: minio\n\taccess-key AKIASECTEST\n\tendpoint s3.invalid\n\tsecret-key SectestS3DDDD4444\n")
      expect(described_class.s3_secret_key('minio')).to eq('SectestS3DDDD4444')
    end

    it 'returns nil for an endpoint that is not in the file' do
      write('s3.cfg', "s3-endpoint: other\n\tsecret-key x\n")
      expect(described_class.s3_secret_key('minio')).to be_nil
    end

    it 'returns nil when the file does not exist' do
      expect(described_class.s3_secret_key('minio')).to be_nil
    end
  end

  describe '.notification_secrets' do
    let(:priv) do
      "smtp: relay\n\tpassword SectestSmtpEEEE5555\n\n" \
        "gotify: alerts\n\ttoken SectestGotifyFFFF6666\n\n" \
        "webhook: hook\n\tsecret name=tok,value=U2VjdGVzdFdlYmhvb2tHR0dHNzc3Nw==\n"
    end

    it 'returns the smtp password' do
      write('notifications-priv.cfg', priv)
      expect(described_class.notification_secrets('smtp', 'relay', 'password')).to eq(['SectestSmtpEEEE5555'])
    end

    it 'returns the gotify token' do
      write('notifications-priv.cfg', priv)
      expect(described_class.notification_secrets('gotify', 'alerts', 'token')).to eq(['SectestGotifyFFFF6666'])
    end

    it 'returns the webhook secret as a raw property string' do
      write('notifications-priv.cfg', priv)
      expect(described_class.notification_secrets('webhook', 'hook', 'secret'))
        .to eq(['name=tok,value=U2VjdGVzdFdlYmhvb2tHR0dHNzc3Nw=='])
    end

    # A webhook may carry several secrets; the field repeats once per entry.
    it 'returns every entry when the field repeats' do
      write('notifications-priv.cfg', "webhook: hook\n\tsecret name=a,value=YQ==\n\tsecret name=b,value=Yg==\n")
      expect(described_class.notification_secrets('webhook', 'hook', 'secret'))
        .to eq(['name=a,value=YQ==', 'name=b,value=Yg=='])
    end

    it 'does not confuse two targets of different types sharing a name' do
      write('notifications-priv.cfg', "smtp: dup\n\tpassword smtppw\n\ngotify: dup\n\ttoken gotifytok\n")
      expect(described_class.notification_secrets('gotify', 'dup', 'token')).to eq(['gotifytok'])
    end

    it 'returns an empty list when the target holds no such secret' do
      write('notifications-priv.cfg', priv)
      expect(described_class.notification_secrets('smtp', 'absent', 'password')).to eq([])
    end

    it 'returns an empty list when the file does not exist' do
      expect(described_class.notification_secrets('smtp', 'relay', 'password')).to eq([])
    end
  end

  describe '.user_password_hash' do
    let(:hash) { '$y$j9T$ExampleFakeSaltNotReal$ExampleFakeYescryptHashNotReal01xxxxxxxxxxx' }

    # shadow.json is keyed by the bare username, realm stripped.
    it 'looks up the hash by the bare username' do
      write('shadow.json', JSON.dump('proxmox' => hash))
      expect(described_class.user_password_hash('proxmox@pbs')).to eq(hash)
    end

    it 'returns nil for a user with no shadow entry' do
      write('shadow.json', JSON.dump('other' => hash))
      expect(described_class.user_password_hash('proxmox@pbs')).to be_nil
    end

    it 'returns nil when shadow.json does not exist' do
      expect(described_class.user_password_hash('proxmox@pbs')).to be_nil
    end

    it 'returns nil for a userid with no username part' do
      write('shadow.json', JSON.dump('proxmox' => hash))
      expect(described_class.user_password_hash('@pbs')).to be_nil
    end
  end
end
