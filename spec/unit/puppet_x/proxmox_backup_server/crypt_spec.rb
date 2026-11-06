# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/proxmox_backup_server/crypt'

RSpec.describe PuppetX::ProxmoxBackupServer::Crypt do
  # Generated with crypt(3) on glibc/libxcrypt for the plaintext 'hunter2'.
  let(:yescrypt) { described_class.generate_hash('hunter2') }

  describe '.verify' do
    it 'accepts the plaintext that produced a yescrypt hash' do
      expect(described_class.verify('hunter2', yescrypt)).to be true
    end

    it 'rejects a different plaintext' do
      expect(described_class.verify('wrong', yescrypt)).to be false
    end

    # Scheme-agnostic: passing the stored hash back as the setting re-derives
    # with whatever scheme it used, so an older $5$ entry still verifies.
    it 'accepts a SHA-256 crypt hash, not just yescrypt' do
      sha256 = described_class.hash_password('hunter2', '$5$abcdefgh')
      expect(described_class.verify('hunter2', sha256)).to be true
    end

    it 'reports drift rather than raising on a malformed hash' do
      expect(described_class.verify('hunter2', '$z$notascheme$xx')).to be false
    end

    it 'reports drift for a nil stored hash' do
      expect(described_class.verify('hunter2', nil)).to be false
    end

    it 'reports drift for an empty stored hash' do
      expect(described_class.verify('hunter2', '')).to be false
    end
  end

  describe '.generate_hash' do
    it 'produces a yescrypt hash' do
      expect(yescrypt).to start_with('$y$')
    end

    it 'produces a different salt each call' do
      expect(described_class.generate_hash('hunter2')).not_to eq(yescrypt)
    end

    it 'produces a hash that verifies against its own plaintext' do
      expect(described_class.verify('hunter2', described_class.generate_hash('hunter2'))).to be true
    end
  end

  describe '.hash_password' do
    it 'returns nil when crypt(3) rejects the setting' do
      expect(described_class.hash_password('hunter2', '$z$')).to be_nil
    end
  end

  # These stub Fiddle, so the memoised handle and functions must be cleared or
  # a previously resolved real one would be reused.
  describe 'libcrypt failures' do
    before(:each) do
      [:@library, :@crypt_function, :@crypt_gensalt_function].each do |ivar|
        described_class.instance_variable_set(ivar, nil)
      end
    end

    after(:each) do
      [:@library, :@crypt_function, :@crypt_gensalt_function].each do |ivar|
        described_class.instance_variable_set(ivar, nil)
      end
    end

    it 'does not hide a libcrypt load failure as a password mismatch' do
      allow(Fiddle::Handle).to receive(:new).and_raise(Fiddle::DLError, 'libcrypt unavailable')
      expect { described_class.verify('hunter2', '$y$x') }
        .to raise_error(Puppet::ResourceError, %r{Failed to load libcrypt\.so\.1.*libcrypt unavailable})
    end

    # A present-but-wrong libcrypt is a different fault from a missing one.
    it 'distinguishes a missing symbol from a load failure' do
      handle = instance_double(Fiddle::Handle)
      allow(Fiddle::Handle).to receive(:new).and_return(handle)
      allow(handle).to receive(:[]).with('crypt').and_raise(Fiddle::DLError, 'unknown symbol crypt')

      expect { described_class.verify('hunter2', '$y$x') }
        .to raise_error(Puppet::ResourceError, %r{Failed to bind crypt\(3\).*unknown symbol crypt})
    end

    it 'treats a NULL result from crypt(3) as a password mismatch' do
      handle = instance_double(Fiddle::Handle)
      crypt_fn = instance_double(Fiddle::Function)
      allow(Fiddle::Handle).to receive(:new).and_return(handle)
      allow(handle).to receive(:[]).with('crypt').and_return(0)
      allow(Fiddle::Function).to receive(:new).and_return(crypt_fn)
      allow(crypt_fn).to receive(:call).and_return(instance_double(Fiddle::Pointer, null?: true))

      expect(described_class.verify('hunter2', '$y$stored-hash')).to be false
    end
  end
end
