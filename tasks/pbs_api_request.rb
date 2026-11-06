#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

def task_input
  stdin = STDIN.read
  return JSON.parse(stdin) unless stdin.strip.empty?

  ENV.select { |key, _value| key.start_with?('PT_') }
     .transform_keys { |key| key.delete_prefix('PT_') }
end

def bool(value)
  [true, 'true', '1', 1].include?(value)
end

def hash_param(input, key)
  value = input[key]
  return {} if value.nil? || value == ''
  return value if value.is_a?(Hash)

  JSON.parse(value)
end

def expand_path(path, path_params)
  path_params.reduce(path) do |expanded, (key, value)|
    expanded.gsub("{#{key}}", URI::DEFAULT_PARSER.escape(value.to_s, %r{[^A-Za-z0-9_.~-]}))
  end
end

def method_class(method)
  {
    'GET'    => Net::HTTP::Get,
    'POST'   => Net::HTTP::Post,
    'PUT'    => Net::HTTP::Put,
    'DELETE' => Net::HTTP::Delete,
  }.fetch(method.to_s.upcase) do
    raise ArgumentError, "Unsupported PBS API method #{method}"
  end
end

def failure(msg, kind, details = {})
  {
    'status'  => details['status_code'] || 'error',
    'success' => false,
    '_error'  => {
      'msg'     => msg,
      'kind'    => kind,
      'details' => details,
    },
  }
end

def parse_body(body)
  return nil if body.nil? || body.empty?

  JSON.parse(body)
end

def error_details(status, body)
  details = { 'status_code' => status }
  details['body'] = begin
    parse_body(body)
                    rescue JSON::ParserError
                      # Non-JSON error body (e.g. proxy HTML): keep a snippet, not the parse error.
                      body.to_s[0, 500]
  end
  details
end

def api_request(input)
  host = input.fetch('host')
  port = Integer(input.fetch('port', 8007))
  token_id = input.fetch('token_id')
  token_secret = input.fetch('token_secret')
  method = input.fetch('method').upcase
  path = expand_path(input.fetch('path'), hash_param(input, 'path_params'))
  query = hash_param(input, 'query')
  body = hash_param(input, 'body')

  raise ArgumentError, 'path must start with /' unless path.start_with?('/')

  uri = URI("https://#{host}:#{port}/api2/json#{path}")
  uri.query = URI.encode_www_form(query) unless query.empty?

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 60
  http.verify_mode = bool(input.fetch('ssl_verify', true)) ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
  ssl_ca_file = input['ssl_ca_file']
  http.ca_file = ssl_ca_file if ssl_ca_file && ssl_ca_file != ''

  request = method_class(method).new(uri)
  request['Authorization'] = "PBSAPIToken=#{token_id}:#{token_secret}"
  request['Content-Type'] = 'application/json'
  request.body = body.to_json unless body.empty?

  response = http.request(request)
  status = response.code.to_i

  unless status.between?(200, 299)
    return failure(
      "PBS API request failed with HTTP #{status} on #{method} #{path}",
      'datajt-proxmox_backup_server/api-error',
      error_details(status, response.body),
    )
  end

  parsed = begin
    parse_body(response.body)
           rescue JSON::ParserError => error
             return failure(
               "PBS API returned invalid JSON on #{method} #{path}: #{error.message}",
               'datajt-proxmox_backup_server/api-error',
               'status_code' => status, 'body' => response.body.to_s[0, 500],
             )
  end
  data = (parsed.is_a?(Hash) && parsed.key?('data')) ? parsed['data'] : parsed

  {
    status: status,
    success: true,
    data: data,
  }
rescue ArgumentError => error
  # Input validation failures (e.g. path not starting with '/', unsupported
  # HTTP method, non-integer port) — not a network/HTTP-layer problem.
  failure(
    "PBS API request failed: #{error.message}",
    'datajt-proxmox_backup_server/validation-error',
    'exception' => error.class.name,
  )
rescue StandardError => error
  failure(
    "PBS API request failed: #{error.class}: #{error.message}",
    'datajt-proxmox_backup_server/connection-error',
    'exception' => error.class.name,
  )
end

if $PROGRAM_NAME == __FILE__
  result = api_request(task_input)
  puts JSON.pretty_generate(result)
  exit(result.key?('_error') ? 1 : 0)
end
