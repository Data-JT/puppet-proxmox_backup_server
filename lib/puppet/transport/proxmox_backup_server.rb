# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'
require 'uri'

# @api private
module Puppet::Transport; end

# Transport for Proxmox Backup Server via its REST API.
#
# NOTE: This class is intentionally NOT a registered Puppet Resource API
# transport. It has no transport schema, does not call register_transport,
# and does not implement the Resource API transport interface
# (verify/facts/close). It is an internal HTTP API client used by the
# pbs_* providers, configured via the Puppet-managed pbs_transport.yaml
# file on the agent. `puppet device` is not supported.
#
# Recognized connection_info keys:
#   :host          (required) PBS host name or IP address
#   :port          (optional) API port, default 8007
#   :token_id      (required) API token ID, e.g. user@realm!token
#   :token_secret  (required) API token secret (String or Sensitive)
#   :ssl_verify    (optional) verify the TLS certificate, default true
#   :ssl_ca_file   (optional) CA bundle path used when ssl_verify is true
#   :task_timeout  (optional) default wait_for_task timeout in seconds,
#                             default 60
class Puppet::Transport::ProxmoxBackupServer
  # Seconds to wait for the TCP and TLS connection to the API.
  OPEN_TIMEOUT = 10
  # Seconds to wait for a response once a request has been sent.
  READ_TIMEOUT = 60
  # Seconds to wait for an async API task (UPID) when :task_timeout is unset.
  DEFAULT_TASK_TIMEOUT = 60

  # Process-wide flag so the "SSL verification disabled" warning is emitted
  # once per Puppet run rather than once per transport instance (each
  # provider builds its own instance, so that could be a dozen warnings).
  # Resettable so specs can isolate themselves.
  class << self
    attr_accessor :ssl_warning_emitted
  end

  def initialize(context, connection_info)
    @host         = connection_info[:host]
    @port         = connection_info[:port] || 8007
    @token_id     = connection_info[:token_id]
    ts = connection_info[:token_secret]
    @token_secret = ts.respond_to?(:unwrap) ? ts.unwrap : ts
    @ssl_verify   = connection_info.fetch(:ssl_verify, true)
    @ssl_ca_file  = connection_info[:ssl_ca_file]
    @task_timeout = connection_info[:task_timeout] || DEFAULT_TASK_TIMEOUT

    validate_connection_info!

    unless @ssl_verify || self.class.ssl_warning_emitted
      context.warning("SSL certificate verification is disabled for #{@host}")
      self.class.ssl_warning_emitted = true
    end

    context.debug("Initialized PBS transport for #{@host}:#{@port}")
  end

  def get(context, path, query = nil)
    request(context, Net::HTTP::Get, sanitize_path(path), nil, query)
  end

  def post(context, path, body = {}, query = nil)
    request(context, Net::HTTP::Post, sanitize_path(path), body, query)
  end

  def put(context, path, body = {}, query = nil)
    request(context, Net::HTTP::Put, sanitize_path(path), body, query)
  end

  def delete(context, path, body = nil, query = nil)
    request(context, Net::HTTP::Delete, sanitize_path(path), body, query)
  end

  # Waits for a PBS async task (identified by a UPID string) to complete.
  # Raises Puppet::ResourceError if the task fails or times out.
  # Does nothing if +upid+ is not a UPID string.
  #
  # The timeout is a wall-clock deadline in seconds. It defaults to the
  # transport's :task_timeout connection_info key (60s if unset) and can be
  # overridden per call. Transient poll errors (e.g. a momentary 5xx on the
  # status endpoint) are retried until the deadline.
  def wait_for_task(context, upid, timeout: nil)
    return unless upid.is_a?(String) && upid.start_with?('UPID:')

    timeout ||= @task_timeout
    node       = upid.split(':')[1]
    deadline   = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    last_error = nil

    loop do
      result = begin
        last_error = nil
        # The UPID is interpolated as path segments. This relies on PBS
        # worker-ids for datastore tasks never containing '/'; the ':'
        # separators are percent-encoded safely by sanitize_path inside
        # get(). Pre-encoding the UPID here would be double-encoded.
        get(context, "/nodes/#{node}/tasks/#{upid}/status")
               rescue Puppet::ResourceError => error
                 last_error = error
                 context.debug("PBS task status poll failed (will retry until deadline): #{error.message}")
                 nil
      end

      if result.is_a?(Hash) && result['status'] == 'stopped'
        exit_status = result['exitstatus']
        return if exit_status == 'OK'
        raise Puppet::ResourceError, "PBS async task failed: #{exit_status || '(no exitstatus)'}"
      end

      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      context.debug("PBS task #{node}/#{upid[0, 40]}... still running, waiting...")
      sleep 1
    end

    message = "PBS async task timed out after #{timeout}s: #{upid}"
    message += " (last poll error: #{last_error.message})" if last_error
    raise Puppet::ResourceError, message
  end

  def call(context, method, path, body: nil, query: nil, path_params: nil)
    expanded_path = expand_path(path, path_params || {})
    request(context, http_method_class(method), validate_expanded_path(expanded_path), body, query)
  end

  def expand_path(path, path_params)
    path_params.reduce(path) do |expanded, (key, value)|
      expanded.gsub("{#{key}}", URI::DEFAULT_PARSER.escape(value.to_s, %r{[^A-Za-z0-9_.~-]}))
    end
  end

  private

  def validate_connection_info!
    { host: @host, token_id: @token_id, token_secret: @token_secret }.each do |key, value|
      next unless value.nil? || value.to_s.empty?
      raise Puppet::ResourceError,
            "PBS transport connection info is missing required key '#{key}' (or it is empty); " \
            'check pbs_transport.yaml / the proxmox_backup_server class parameters'
    end
    @token_secret = @token_secret.to_s
  end

  # Percent-encodes each path segment and rejects '.'/'..' traversal
  # segments. Providers interpolate raw resource titles into paths; this is
  # defense-in-depth on top of type-level namevar validation.
  def sanitize_path(path)
    unless path.is_a?(String) && path.start_with?('/')
      raise Puppet::ResourceError, "PBS API path must be a string starting with '/', got #{path.inspect}"
    end

    path.split('/', -1).map { |segment|
      if ['.', '..'].include?(segment)
        raise Puppet::ResourceError, "PBS API path #{path.inspect} contains invalid path segment #{segment.inspect}"
      end
      URI::DEFAULT_PARSER.escape(segment, %r{[^A-Za-z0-9_.~-]})
    }.join('/')
  end

  # Enforces the sanitize_path invariants on a call() path. The placeholder
  # values were already percent-encoded by expand_path, so running the
  # expanded path through sanitize_path would double-encode them; instead we
  # validate: it must start with '/', contain no '.'/'..' dot-segments, and
  # no raw whitespace (static template segments must be literal API paths
  # that need no encoding).
  def validate_expanded_path(path)
    unless path.is_a?(String) && path.start_with?('/')
      raise Puppet::ResourceError, "PBS API path must be a string starting with '/', got #{path.inspect}"
    end
    if path.split('/', -1).any? { |segment| ['.', '..'].include?(segment) }
      raise Puppet::ResourceError, "PBS API path #{path.inspect} contains an invalid dot path segment"
    end
    raise Puppet::ResourceError, "PBS API path #{path.inspect} contains raw whitespace" if path.match?(%r{\s})
    path
  end

  def request(context, method_class, path, body = nil, query = nil)
    uri  = build_uri(path, query)
    req  = method_class.new(uri)
    req['Authorization'] = "PBSAPIToken=#{@token_id}:#{@token_secret}"
    req['Content-Type']  = 'application/json'
    req.body = body.to_json if body && !body.empty?

    context.debug("PBS API #{method_class::METHOD} #{uri.request_uri}")
    response = begin
      http_connection.request(req)
               rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
                      Errno::ETIMEDOUT, SocketError, IOError,
                      OpenSSL::SSL::SSLError, Net::OpenTimeout, Net::ReadTimeout => error
                 raise Puppet::ResourceError,
                       "PBS API connection to #{@host}:#{@port} failed: #{error.class}: #{error.message}"
    end
    handle_response(context, response, path)
  end

  def build_uri(path, query)
    uri = URI("https://#{@host}:#{@port}/api2/json#{path}")
    uri.query = URI.encode_www_form(query) if query && !query.empty?
    uri
  end

  def http_method_class(method)
    {
      'GET'    => Net::HTTP::Get,
      'POST'   => Net::HTTP::Post,
      'PUT'    => Net::HTTP::Put,
      'DELETE' => Net::HTTP::Delete,
    }.fetch(method.to_s.upcase) do
      raise Puppet::ResourceError, "Unsupported PBS API method #{method}"
    end
  end

  def http_connection
    @http_connection ||= Net::HTTP.new(@host, @port).tap do |http|
      http.use_ssl      = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      if @ssl_verify
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.ca_file     = @ssl_ca_file if @ssl_ca_file
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      http.start
    end
  end

  def handle_response(_context, response, path)
    code = response.code
    body = response.body
    unless code.to_i.between?(200, 299)
      raise Puppet::ResourceError,
            "PBS API error #{code} on #{path}: #{body}"
    end
    return nil if body.nil? || body.empty?
    parsed = JSON.parse(body)
    (parsed.is_a?(Hash) && parsed.key?('data')) ? parsed['data'] : parsed
  rescue JSON::ParserError => error
    raise Puppet::ResourceError, "PBS API returned invalid JSON on #{path}: #{error.message}"
  end
end
