#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'optparse'
require 'uri'
require 'yaml'

RESOURCE_MAPPINGS = {
  datastores: {
    endpoint: '/config/datastore',
    key:      'name',
    fields:   {
      'path'        => 'path',
      'comment'     => 'comment',
      'gc-schedule' => 'gc_schedule',
    },
  },
  users: {
    endpoint: '/access/users',
    key:      'userid',
    fields:   {
      'comment'   => 'comment',
      'email'     => 'email',
      'enable'    => 'enable',
      'expire'    => 'expire',
      'firstname' => 'firstname',
      'lastname'  => 'lastname',
    },
    booleans: ['enable'],
  },
  acls: {
    endpoint: '/access/acl',
    key_proc: ->(entry) {
      role = entry['roleid'] || entry['role']
      "#{entry.fetch('path')}|#{entry.fetch('ugid')}|#{role}"
    },
    fields:   {
      'propagate' => 'propagate',
    },
    booleans: ['propagate'],
  },
  remotes: {
    endpoint: '/config/remote',
    key:      'name',
    fields:   {
      'host'        => 'host',
      'port'        => 'port',
      'auth-id'     => 'userid',
      'fingerprint' => 'fingerprint',
      'comment'     => 'comment',
    },
    password_placeholder: true,
  },
  sync_jobs: {
    endpoint: '/config/sync',
    key:      'id',
    fields:   {
      'store'           => 'store',
      'remote'          => 'remote',
      'remote-store'    => 'remote_store',
      'schedule'        => 'job_schedule',
      'remove-vanished' => 'remove_vanished',
      'comment'         => 'comment',
    },
    booleans: ['remove-vanished'],
  },
  prune_jobs: {
    endpoint: '/config/prune',
    key:      'id',
    fields:   {
      'store'        => 'store',
      'schedule'     => 'job_schedule',
      'ns'           => 'ns',
      'keep-last'    => 'keep_last',
      'keep-hourly'  => 'keep_hourly',
      'keep-daily'   => 'keep_daily',
      'keep-weekly'  => 'keep_weekly',
      'keep-monthly' => 'keep_monthly',
      'keep-yearly'  => 'keep_yearly',
      'comment'      => 'comment',
    },
  },
  verification_jobs: {
    endpoint: '/config/verify',
    key:      'id',
    fields:   {
      'store'           => 'store',
      'schedule'        => 'job_schedule',
      'outdated-after'  => 'outdated_after',
      'ignore-verified' => 'ignore_verified',
      'comment'         => 'comment',
    },
    booleans: ['ignore-verified'],
  },
}.freeze

DEFAULT_OPTIONS = {
  host:                         'localhost',
  port:                         8007,
  ssl_verify:                   true,
  skip_errors:                  false,
  remote_password_placeholder:  'CHANGE_ME_WRITE_ONLY_REMOTE_PASSWORD',
  include_transport_parameters: false,
}.freeze

# Minimal standalone PBS API client used only by this import tool.
# The Puppet module itself talks to PBS through
# lib/puppet/transport/proxmox_backup_server.rb; this class exists so the
# tool works without a Puppet installation.
class PbsApiClient
  def initialize(options)
    @host         = options.fetch(:host)
    @port         = options.fetch(:port)
    @token_id     = options.fetch(:token_id)
    @token_secret = options.fetch(:token_secret)
    @ssl_verify   = options.fetch(:ssl_verify)
    @ssl_ca_file  = options[:ssl_ca_file]
  end

  def get(path)
    uri = URI("https://#{@host}:#{@port}/api2/json#{path}")
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "PBSAPIToken=#{@token_id}:#{@token_secret}"
    request['Content-Type'] = 'application/json'

    response = http.request(request)
    unless response.code.to_i.between?(200, 299)
      raise "PBS API error #{response.code} on #{path}: #{response.body}"
    end

    parsed = JSON.parse(response.body)
    (parsed.is_a?(Hash) && parsed.key?('data')) ? parsed['data'] : parsed
  end

  private

  def http
    @http ||= Net::HTTP.new(@host, @port).tap do |connection|
      connection.use_ssl = true
      connection.open_timeout = 10
      connection.read_timeout = 60
      if @ssl_verify
        connection.verify_mode = OpenSSL::SSL::VERIFY_PEER
        connection.ca_file = @ssl_ca_file if @ssl_ca_file
      else
        connection.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end
  end
end

def normalize_boolean(value)
  return true if [true, 1, '1', 'true'].include?(value)
  return false if [false, 0, '0', 'false'].include?(value)

  value
end

def normalize_entry(entry, mapping, options)
  attributes = { 'ensure' => 'present' }
  boolean_fields = mapping.fetch(:booleans, [])

  mapping.fetch(:fields).each do |api_field, puppet_field|
    next unless entry.key?(api_field)

    value = entry[api_field]
    next if value.nil?

    value = normalize_boolean(value) if boolean_fields.include?(api_field)
    attributes[puppet_field] = value
  end

  if mapping[:password_placeholder]
    attributes['password'] = options.fetch(:remote_password_placeholder)
  end

  attributes
end

def resource_key(entry, mapping)
  return mapping.fetch(:key_proc).call(entry) if mapping.key?(:key_proc)

  entry.fetch(mapping.fetch(:key))
end

def build_hiera_data(client, options)
  data = {}

  if options[:include_transport_parameters]
    data['lookup_options'] = {
      'proxmox_backup_server::token_secret' => {
        'convert_to' => 'Sensitive',
      },
    }
    data['proxmox_backup_server::host'] = options.fetch(:host)
    data['proxmox_backup_server::port'] = options.fetch(:port)
    data['proxmox_backup_server::ssl_verify'] = options.fetch(:ssl_verify)
    data['proxmox_backup_server::ssl_ca_file'] = options[:ssl_ca_file] if options[:ssl_ca_file]
    data['proxmox_backup_server::token_id'] = options.fetch(:token_id)
    data['proxmox_backup_server::token_secret'] = 'CHANGE_ME_TOKEN_SECRET'
  end

  RESOURCE_MAPPINGS.each do |name, mapping|
    resources = {}
    begin
      Array(client.get(mapping.fetch(:endpoint))).each do |entry|
        resources[resource_key(entry, mapping)] = normalize_entry(entry, mapping, options)
      end
    rescue StandardError => error
      raise unless options[:skip_errors]

      warn "Skipping #{mapping.fetch(:endpoint)}: #{error.message}"
    end

    data["proxmox_backup_server::resources::#{name}"] = resources unless resources.empty?
  end

  data
end

def load_transport_config(path)
  config = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
  unless config.is_a?(Hash)
    warn "Transport config #{path} is empty or not a YAML mapping"
    exit 1
  end
  config.transform_keys(&:to_sym)
rescue SystemCallError => error
  warn "Cannot read transport config #{path}: #{error.message}"
  exit 1
end

def parse_options(argv)
  options = DEFAULT_OPTIONS.dup

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: pbs_hiera_import.rb [options]'

    opts.on('--transport-config PATH', 'Read connection settings from pbs_transport.yaml') do |path|
      options.merge!(load_transport_config(path))
    end
    opts.on('--host HOST', 'PBS API host (default: localhost)') { |value| options[:host] = value }
    opts.on('--port PORT', Integer, 'PBS API port (default: 8007)') { |value| options[:port] = value }
    opts.on('--token-id TOKEN_ID', 'PBS API token ID') { |value| options[:token_id] = value }
    opts.on('--token-secret SECRET',
            'PBS API token secret. WARNING: visible in process lists and shell',
            'history; prefer --token-secret-file or --transport-config') do |value|
      options[:token_secret] = value
    end
    opts.on('--token-secret-file PATH', 'Read PBS API token secret from a file') do |path|
      options[:token_secret] = File.read(path).strip
    rescue SystemCallError => error
      warn "Cannot read token secret file #{path}: #{error.message}"
      exit 1
    end
    opts.on('--[no-]ssl-verify', 'Verify the PBS TLS certificate (default: enabled)') do |value|
      options[:ssl_verify] = value
    end
    opts.on('--ssl-ca-file PATH', 'CA bundle path used when TLS verification is enabled') { |value| options[:ssl_ca_file] = value }
    opts.on('--output PATH', 'Write YAML to PATH instead of stdout') { |value| options[:output] = value }
    opts.on('--skip-errors', 'Warn and continue when an endpoint cannot be imported') { options[:skip_errors] = true }
    opts.on('--include-transport-parameters', 'Also emit proxmox_backup_server class parameters') do
      options[:include_transport_parameters] = true
    end
    opts.on('--remote-password-placeholder VALUE', 'Placeholder for write-only remote passwords') do |value|
      options[:remote_password_placeholder] = value
    end
    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end

  parser.parse!(argv)

  missing = []
  missing << '--token-id' unless options[:token_id]
  missing << '--token-secret or --token-secret-file' unless options[:token_secret]
  raise OptionParser::MissingArgument, missing.join(', ') unless missing.empty?

  options
end

begin
  options = parse_options(ARGV)
  client = PbsApiClient.new(options)
  yaml = build_hiera_data(client, options).to_yaml

  if options[:output]
    File.write(options[:output], yaml)
  else
    puts yaml
  end
rescue OptionParser::ParseError => error
  warn error.message
  exit 1
end
