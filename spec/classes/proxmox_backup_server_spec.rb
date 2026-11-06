# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'proxmox_backup_server', type: :class do
  let(:secret_value) { 'supersecrettoken' }
  let(:default_config_file) { File.join(Puppet.settings[:confdir], 'pbs_transport.yaml') }
  let(:params) do
    {
      token_id:     'root@pam!puppet',
      token_secret: sensitive(secret_value),
    }
  end

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile.with_all_deps }

      describe 'pbs_transport.yaml' do
        it {
          is_expected.to contain_file(default_config_file).with(
            'ensure' => 'file',
            'mode'   => '0600',
            'owner'  => 'root',
            'group'  => 'root',
          )
        }

        it 'marks content as sensitive so Puppet never logs it in reports' do
          resource = catalogue.resource('File', default_config_file)
          expect(resource.sensitive_parameters).to include(:content)
        end

        it 'does not expose token_secret in any non-sensitive catalog parameter' do
          catalogue.resources.each do |resource|
            sensitive = resource.sensitive_parameters
            resource.to_hash.each do |param, value|
              next if sensitive.include?(param)

              expect(value.to_s).not_to include(secret_value),
                "token_secret appeared unprotected in #{resource.ref}[#{param}]"
            end
          end
        end
      end

      context 'with custom config_file' do
        let(:params) { super().merge(config_file: '/opt/pbs_transport.yaml') }

        it { is_expected.to contain_file('/opt/pbs_transport.yaml').with('mode' => '0600') }
        it { is_expected.to contain_file(default_config_file).with('ensure' => 'link', 'target' => '/opt/pbs_transport.yaml') }
      end

      # The default path follows the AGENT's confdir (fact), not the compiling
      # server's $settings::confdir: an AIO server compiling for a Debian agent
      # must not place the file, or a link, under /etc/puppetlabs/puppet there.
      context 'when the agent reports a different confdir than the server' do
        let(:facts) { os_facts.merge(proxmox_backup_server_confdir: '/etc/puppet') }

        it { is_expected.to contain_file('/etc/puppet/pbs_transport.yaml').with('ensure' => 'file', 'mode' => '0600') }
        it { is_expected.not_to contain_file(default_config_file) }

        context 'with custom config_file' do
          let(:params) { super().merge(config_file: '/opt/pbs_transport.yaml') }

          it { is_expected.to contain_file('/etc/puppet/pbs_transport.yaml').with('ensure' => 'link', 'target' => '/opt/pbs_transport.yaml') }
          it { is_expected.not_to contain_file(default_config_file) }
        end
      end

      context 'with a malformed token_id' do
        let(:params) { super().merge(token_id: 'root-pam-puppet') }

        it { is_expected.to compile.and_raise_error(%r{token_id}) }
      end

      context 'with a relative config_file' do
        let(:params) { super().merge(config_file: 'relative/pbs_transport.yaml') }

        it { is_expected.to compile.and_raise_error(%r{config_file}) }
      end

      context 'with a relative ssl_ca_file' do
        let(:params) { super().merge(ssl_ca_file: 'certs/ca.crt') }

        it { is_expected.to compile.and_raise_error(%r{ssl_ca_file}) }
      end

      context 'with task_timeout set' do
        let(:params) { super().merge(task_timeout: 120) }

        it { is_expected.to compile.with_all_deps }

        it 'emits task_timeout in the transport config' do
          content = catalogue.resource('File', default_config_file)[:content]
          content = content.unwrap if content.respond_to?(:unwrap)
          expect(content).to match(%r{^task_timeout: 120$})
        end
      end

      context 'without task_timeout' do
        it 'does not emit task_timeout in the transport config' do
          content = catalogue.resource('File', default_config_file)[:content]
          content = content.unwrap if content.respond_to?(:unwrap)
          expect(content).not_to match(%r{task_timeout})
        end
      end

      context 'with all parameters' do
        let(:params) do
          super().merge(
            host:        'pbs.example.com',
            port:        9007,
            ssl_verify:  true,
            ssl_ca_file: '/etc/ssl/certs/my-ca.crt',
          )
        end

        it { is_expected.to compile.with_all_deps }
      end
    end
  end
end
