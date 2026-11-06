# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'proxmox_backup_server::resources', type: :class do
  let(:params) do
    {
      datastores: {
        'backup' => {
          'ensure' => 'present',
          'path'   => '/mnt/datastore/backup',
        },
      },
      users: {
        'backup@pbs' => {
          'ensure' => 'present',
          'enable' => true,
        },
        'jdoe@ldap1' => {
          'ensure' => 'present',
          'enable' => true,
        },
      },
      realms: {
        'ldap1' => {
          'ensure'    => 'present',
          'type'      => 'ldap',
          'server1'   => 'ldap.example.com',
          'base_dn'   => 'dc=example,dc=com',
          'user_attr' => 'uid',
        },
      },
      s3_endpoints: {
        's3main' => {
          'ensure'     => 'present',
          'endpoint'   => 'https://s3.example.com',
          'access_key' => 'AKIAEXAMPLE',
          'secret_key' => 'placeholder',
          'region'     => 'eu-central-1',
        },
      },
      node_config: {
        'pbs' => {
          'ensure'     => 'present',
          'email_from' => 'pbs@example.com',
        },
      },
      api_tokens: {
        'backup@pbs!automation' => {
          'ensure' => 'present',
          'enable' => true,
        },
      },
      acls: {
        '/datastore/backup|backup@pbs|DatastoreBackup' => {
          'ensure'    => 'present',
          'propagate' => true,
        },
        '/datastore/backup|backup@pbs!automation|DatastoreBackup' => {
          'ensure'    => 'present',
          'propagate' => true,
        },
      },
      remotes: {
        'offsite' => {
          'ensure'   => 'present',
          'host'     => 'pbs-offsite.example.com',
          'userid'   => 'sync@pbs',
          'password' => 'placeholder',
        },
      },
      sync_jobs: {
        'sync-offsite' => {
          'ensure'       => 'present',
          'store'        => 'backup',
          'remote'       => 'offsite',
          'remote_store' => 'backup',
        },
      },
      prune_jobs: {
        'prune-backup' => {
          'ensure'       => 'present',
          'store'        => 'backup',
          'job_schedule' => 'daily',
        },
      },
      verification_jobs: {
        'verify-backup' => {
          'ensure' => 'present',
          'store'  => 'backup',
        },
      },
      notification_targets: {
        'operations' => {
          'ensure' => 'present',
          'type'   => 'sendmail',
          'mailto' => ['ops@example.com'],
        },
      },
      notification_matchers: {
        'all-errors' => {
          'ensure'         => 'present',
          'target'         => ['operations'],
          'match_severity' => ['error'],
        },
      },
    }
  end

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_pbs_datastore('backup').with('path' => '/mnt/datastore/backup') }
      it { is_expected.to contain_pbs_user('backup@pbs').with('enable' => true) }
      it { is_expected.to contain_pbs_acl('/datastore/backup|backup@pbs|DatastoreBackup').with('propagate' => true) }
      it { is_expected.to contain_pbs_remote('offsite').with('host' => 'pbs-offsite.example.com') }
      it { is_expected.to contain_pbs_sync_job('sync-offsite').with('remote' => 'offsite') }
      it { is_expected.to contain_pbs_prune_job('prune-backup').with('job_schedule' => 'daily') }
      it { is_expected.to contain_pbs_verification_job('verify-backup').with('store' => 'backup') }
      it { is_expected.to contain_pbs_realm('ldap1').with('type' => 'ldap', 'server1' => 'ldap.example.com') }
      it { is_expected.to contain_pbs_s3_endpoint('s3main').with('endpoint' => 'https://s3.example.com', 'access_key' => 'AKIAEXAMPLE') }
      it { is_expected.to contain_pbs_node_config('pbs').with('email_from' => 'pbs@example.com') }
      it { is_expected.to contain_pbs_user('jdoe@ldap1').that_requires('Pbs_realm[ldap1]') }
      it { is_expected.to contain_pbs_api_token('backup@pbs!automation').that_requires('Pbs_user[backup@pbs]') }
      it { is_expected.to contain_pbs_acl('/datastore/backup|backup@pbs|DatastoreBackup').that_requires('Pbs_user[backup@pbs]') }
      it { is_expected.to contain_pbs_acl('/datastore/backup|backup@pbs!automation|DatastoreBackup').that_requires('Pbs_api_token[backup@pbs!automation]') }
      it { is_expected.to contain_pbs_sync_job('sync-offsite').that_requires('Pbs_datastore[backup]') }
      it { is_expected.to contain_pbs_sync_job('sync-offsite').that_requires('Pbs_remote[offsite]') }
      it { is_expected.to contain_pbs_prune_job('prune-backup').that_requires('Pbs_datastore[backup]') }
      it { is_expected.to contain_pbs_verification_job('verify-backup').that_requires('Pbs_datastore[backup]') }
      it { is_expected.to contain_pbs_notification_matcher('all-errors').that_requires('Pbs_notification_target[operations]') }
    end
  end
end
