# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'puppet/transport/proxmox_backup_server'

RSpec.describe Puppet::Transport::ProxmoxBackupServer do
  subject(:transport) { described_class.new(context, connection_info) }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext') }
  let(:token_secret_obj) { instance_double('Puppet::Pops::Types::PSensitiveType::Sensitive', unwrap: 'supersecret') }

  let(:connection_info) do
    {
      host:         'pbs.example.com',
      port:         8007,
      token_id:     'user@realm!mytoken',
      token_secret: token_secret_obj,
      ssl_verify:   false,
    }
  end

  let(:base_url)     { 'https://pbs.example.com:8007/api2/json' }
  let(:auth_header)  { 'PBSAPIToken=user@realm!mytoken:supersecret' }
  let(:json_headers) { { 'Authorization' => auth_header, 'Content-Type' => 'application/json' } }

  before(:each) do
    allow(context).to receive(:debug)
    allow(context).to receive(:warning)
    described_class.ssl_warning_emitted = false
  end

  describe '#initialize' do
    it 'raises Puppet::ResourceError when host is missing' do
      expect { described_class.new(context, connection_info.merge(host: nil)) }
        .to raise_error(Puppet::ResourceError, %r{missing required key 'host'})
    end

    it 'raises Puppet::ResourceError when host is empty' do
      expect { described_class.new(context, connection_info.merge(host: '')) }
        .to raise_error(Puppet::ResourceError, %r{missing required key 'host'})
    end

    it 'raises Puppet::ResourceError when token_id is missing' do
      expect { described_class.new(context, connection_info.merge(token_id: nil)) }
        .to raise_error(Puppet::ResourceError, %r{missing required key 'token_id'})
    end

    it 'raises Puppet::ResourceError when token_secret is missing' do
      expect { described_class.new(context, connection_info.merge(token_secret: nil)) }
        .to raise_error(Puppet::ResourceError, %r{missing required key 'token_secret'})
    end

    it 'raises Puppet::ResourceError when token_secret is empty' do
      expect { described_class.new(context, connection_info.merge(token_secret: '')) }
        .to raise_error(Puppet::ResourceError, %r{missing required key 'token_secret'})
    end

    it 'warns once when SSL verification is disabled' do
      expect(context).to receive(:warning)
        .with(a_string_matching(%r{SSL certificate verification is disabled for pbs\.example\.com})).once
      described_class.new(context, connection_info)
    end

    it 'does not warn again when a second instance is created in the same process' do
      expect(context).to receive(:warning)
        .with(a_string_matching(%r{SSL certificate verification is disabled})).once
      described_class.new(context, connection_info)
      described_class.new(context, connection_info)
    end

    it 'does not warn when SSL verification is enabled' do
      expect(context).not_to receive(:warning)
      described_class.new(context, connection_info.merge(ssl_verify: true))
    end

    it 'does not warn when the ssl_verify key is absent (defaults to verification on)' do
      info = connection_info.dup
      info.delete(:ssl_verify)
      expect(context).not_to receive(:warning)
      described_class.new(context, info)
    end
  end

  describe '#get' do
    it 'returns unwrapped data array on success' do
      stub_request(:get, "#{base_url}/config/datastore")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": [{"name": "ds1"}]}')

      expect(transport.get(context, '/config/datastore')).to eq([{ 'name' => 'ds1' }])
    end

    it 'returns unwrapped data hash on success' do
      stub_request(:get, "#{base_url}/version")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": {"version": "2.4.3"}}')

      expect(transport.get(context, '/version')).to eq({ 'version' => '2.4.3' })
    end

    it 'encodes query parameters' do
      stub_request(:get, "#{base_url}/access/acl?exact=1&path=%2Fdatastore%2Fbackup")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": []}')

      expect(transport.get(context, '/access/acl', 'exact' => 1, 'path' => '/datastore/backup')).to eq([])
    end
  end

  describe 'path segment escaping' do
    it 'percent-encodes spaces in path segments' do
      stub_request(:get, "#{base_url}/config/datastore/my%20store")
        .to_return(status: 200, body: '{"data": null}')

      expect { transport.get(context, '/config/datastore/my store') }.not_to raise_error
    end

    it 'percent-encodes # and ? in path segments' do
      stub_request(:delete, "#{base_url}/config/datastore/a%23b%3Fc")
        .to_return(status: 200, body: '{"data": null}')

      expect { transport.delete(context, '/config/datastore/a#b?c') }.not_to raise_error
    end

    it 'does not encode the / separators' do
      stub_request(:put, "#{base_url}/config/datastore/plain")
        .to_return(status: 200, body: '{"data": null}')

      expect { transport.put(context, '/config/datastore/plain', { 'comment' => 'x' }) }.not_to raise_error
    end

    it 'rejects .. path segments without making a request' do
      expect { transport.get(context, '/config/datastore/../../access/users') }
        .to raise_error(Puppet::ResourceError, %r{invalid path segment})
      expect(WebMock).not_to have_requested(:get, %r{pbs\.example\.com})
    end

    it 'rejects . path segments' do
      expect { transport.post(context, '/config/./datastore', {}) }
        .to raise_error(Puppet::ResourceError, %r{invalid path segment})
    end

    it 'rejects paths that do not start with /' do
      expect { transport.get(context, 'config/datastore') }
        .to raise_error(Puppet::ResourceError, %r{must be a string starting with '/'})
    end
  end

  describe '#post' do
    it 'sends request body and returns unwrapped data' do
      stub_request(:post, "#{base_url}/config/datastore")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": null}')

      result = transport.post(context, '/config/datastore', { 'name' => 'ds1', 'path' => '/mnt/ds1' })
      expect(result).to be_nil
    end
  end

  describe '#put' do
    it 'sends request and returns unwrapped data' do
      stub_request(:put, "#{base_url}/config/datastore/ds1")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": null}')

      expect(transport.put(context, '/config/datastore/ds1', { 'comment' => 'updated' })).to be_nil
    end
  end

  describe '#delete' do
    it 'sends request and returns unwrapped data' do
      stub_request(:delete, "#{base_url}/config/datastore/ds1")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": null}')

      expect(transport.delete(context, '/config/datastore/ds1')).to be_nil
    end
  end

  describe '#call' do
    it 'dispatches by HTTP method and expands path parameters' do
      stub_request(:put, "#{base_url}/config/datastore/my%20store")
        .with(headers: json_headers, body: '{"comment":"updated"}')
        .to_return(status: 200, body: '{"data": null}')

      expect(
        transport.call(
          context,
          'PUT',
          '/config/datastore/{name}',
          path_params: { 'name' => 'my store' },
          body:        { 'comment' => 'updated' },
        ),
      ).to be_nil
    end

    it 'raises for unsupported methods' do
      expect { transport.call(context, 'PATCH', '/version') }
        .to raise_error(Puppet::ResourceError, %r{Unsupported PBS API method PATCH})
    end

    it 'rejects dot-segment traversal in expanded paths without making a request' do
      expect { transport.call(context, 'GET', '/config/datastore/{name}/../../access/users', path_params: { 'name' => 'ds1' }) }
        .to raise_error(Puppet::ResourceError, %r{invalid dot path segment})
      expect(WebMock).not_to have_requested(:get, %r{pbs\.example\.com})
    end

    it 'rejects paths that do not start with /' do
      expect { transport.call(context, 'GET', 'config/datastore') }
        .to raise_error(Puppet::ResourceError, %r{must be a string starting with '/'})
    end

    it 'rejects raw whitespace in static template segments without making a request' do
      expect { transport.call(context, 'GET', '/config/data store') }
        .to raise_error(Puppet::ResourceError, %r{raw whitespace})
      expect(WebMock).not_to have_requested(:get, %r{pbs\.example\.com})
    end

    it 'does not double-encode path parameter values escaped during expansion' do
      stub_request(:get, "#{base_url}/config/datastore/my%20store")
        .to_return(status: 200, body: '{"data": null}')

      expect { transport.call(context, 'GET', '/config/datastore/{name}', path_params: { 'name' => 'my store' }) }
        .not_to raise_error
    end
  end

  describe 'error handling' do
    it 'raises Puppet::ResourceError on 401' do
      stub_request(:get, "#{base_url}/config/datastore")
        .to_return(status: 401, body: 'Unauthorized')

      expect { transport.get(context, '/config/datastore') }
        .to raise_error(Puppet::ResourceError, %r{401})
    end

    it 'raises Puppet::ResourceError on 404' do
      stub_request(:get, "#{base_url}/missing")
        .to_return(status: 404, body: 'Not Found')

      expect { transport.get(context, '/missing') }
        .to raise_error(Puppet::ResourceError, %r{404})
    end

    it 'raises Puppet::ResourceError on 500' do
      stub_request(:get, "#{base_url}/config/datastore")
        .to_return(status: 500, body: 'Internal Server Error')

      expect { transport.get(context, '/config/datastore') }
        .to raise_error(Puppet::ResourceError, %r{500})
    end

    it 'raises Puppet::ResourceError when a successful response contains invalid JSON' do
      stub_request(:get, "#{base_url}/version")
        .to_return(status: 200, body: 'not-json')

      expect { transport.get(context, '/version') }
        .to raise_error(Puppet::ResourceError, %r{invalid JSON on /version})
    end
  end

  describe 'connection error wrapping' do
    it 'wraps connection refused errors with host and port' do
      stub_request(:get, "#{base_url}/version").to_raise(Errno::ECONNREFUSED)

      expect { transport.get(context, '/version') }
        .to raise_error(Puppet::ResourceError, %r{PBS API connection to pbs\.example\.com:8007 failed})
    end

    it 'wraps timeouts with host and port' do
      stub_request(:get, "#{base_url}/version").to_timeout

      expect { transport.get(context, '/version') }
        .to raise_error(Puppet::ResourceError, %r{PBS API connection to pbs\.example\.com:8007 failed})
    end

    it 'wraps DNS resolution failures' do
      stub_request(:get, "#{base_url}/version").to_raise(SocketError.new('getaddrinfo: Name or service not known'))

      expect { transport.get(context, '/version') }
        .to raise_error(Puppet::ResourceError, %r{failed: SocketError: getaddrinfo})
    end

    it 'wraps TLS errors' do
      stub_request(:get, "#{base_url}/version")
        .to_raise(OpenSSL::SSL::SSLError.new('certificate verify failed'))

      expect { transport.get(context, '/version') }
        .to raise_error(Puppet::ResourceError, %r{failed: OpenSSL::SSL::SSLError: certificate verify failed})
    end

    it 'does not leak the token secret in wrapped errors' do
      stub_request(:get, "#{base_url}/version").to_raise(Errno::ECONNREFUSED)

      transport.get(context, '/version')
      raise 'expected an error'
    rescue Puppet::ResourceError => error
      expect(error.message).not_to include('supersecret')
    end
  end

  describe 'empty response body' do
    it 'returns nil when body is an empty string' do
      stub_request(:delete, "#{base_url}/config/datastore/ds1")
        .to_return(status: 200, body: '')

      expect(transport.delete(context, '/config/datastore/ds1')).to be_nil
    end
  end

  describe 'TLS configuration' do
    let(:ok_response) { instance_double(Net::HTTPResponse, code: '200', body: '{"data": null}') }
    let(:http_double) { instance_double(Net::HTTP) }

    before(:each) do
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:verify_mode=)
      allow(http_double).to receive(:start)
      allow(http_double).to receive(:request).and_return(ok_response)
    end

    it 'opens connections within 10 seconds and waits up to 60 seconds for a response' do
      expect(http_double).to receive(:open_timeout=).with(10)
      expect(http_double).to receive(:read_timeout=).with(60)
      transport.get(context, '/version')
    end

    it 'sets VERIFY_NONE when ssl_verify is false' do
      expect(http_double).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
      transport.get(context, '/version')
    end

    context 'when the ssl_verify key is absent' do
      let(:connection_info) do
        info = super().dup
        info.delete(:ssl_verify)
        info
      end

      it 'defaults to VERIFY_PEER' do
        expect(http_double).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
        transport.get(context, '/version')
      end
    end

    context 'when ssl_verify is true' do
      let(:connection_info) { super().merge(ssl_verify: true, ssl_ca_file: '/etc/ssl/custom-ca.pem') }

      before(:each) do
        allow(http_double).to receive(:ca_file=)
      end

      it 'sets VERIFY_PEER' do
        expect(http_double).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
        transport.get(context, '/version')
      end

      it 'sets ca_file when ssl_ca_file is provided' do
        expect(http_double).to receive(:ca_file=).with('/etc/ssl/custom-ca.pem')
        transport.get(context, '/version')
      end
    end
  end

  describe 'token_secret handling' do
    it 'accepts a Sensitive-wrapped token_secret' do
      sensitive = instance_double('Puppet::Pops::Types::PSensitiveType::Sensitive', unwrap: 'mytoken')
      info = connection_info.merge(token_secret: sensitive)
      t = described_class.new(context, info)
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data": null}')
      expect { t.get(context, '/version') }.not_to raise_error
    end

    it 'accepts a plain String token_secret (provider-mode without device credentials)' do
      info = connection_info.merge(token_secret: 'plainstring')
      t = described_class.new(context, info)
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data": null}')
      expect { t.get(context, '/version') }.not_to raise_error
    end
  end

  describe '#wait_for_task' do
    let(:node) { 'pbs' }
    let(:upid) { 'UPID:pbs:000003CE:0000029B:00000018:6A232153:create-datastore:backup:puppet@pbs!puppet:' }
    let(:encoded_upid) { URI.encode_www_form_component(upid) }
    let(:status_url) { "#{base_url}/nodes/#{node}/tasks/#{encoded_upid}/status" }

    it 'returns immediately when upid is nil' do
      expect { transport.wait_for_task(context, nil) }.not_to raise_error
    end

    it 'returns immediately when upid is not a UPID string' do
      expect { transport.wait_for_task(context, 'not-a-upid') }.not_to raise_error
    end

    it 'returns without error when task completes with OK exitstatus' do
      stub_request(:get, status_url)
        .to_return(status: 200, body: '{"data": {"status": "stopped", "exitstatus": "OK"}}')

      expect { transport.wait_for_task(context, upid) }.not_to raise_error
    end

    it 'raises ResourceError when task fails' do
      stub_request(:get, status_url)
        .to_return(status: 200, body: '{"data": {"status": "stopped", "exitstatus": "TASK ERROR: datastore path not empty"}}')

      expect { transport.wait_for_task(context, upid) }
        .to raise_error(Puppet::ResourceError, %r{datastore path not empty})
    end

    it 'polls until the task stops running' do
      stub_request(:get, status_url)
        .to_return(
          { status: 200, body: '{"data": {"status": "running"}}' },
          { status: 200, body: '{"data": {"status": "stopped", "exitstatus": "OK"}}' },
        )
      expect(transport).to receive(:sleep).with(1).once

      expect { transport.wait_for_task(context, upid) }.not_to raise_error
    end

    it 'tolerates a transient poll error and keeps polling until the deadline' do
      stub_request(:get, status_url)
        .to_return(
          { status: 500, body: 'Internal Server Error' },
          { status: 200, body: '{"data": {"status": "stopped", "exitstatus": "OK"}}' },
        )
      allow(transport).to receive(:sleep)

      expect { transport.wait_for_task(context, upid, timeout: 10) }.not_to raise_error
    end

    it 'raises ResourceError when the wall-clock deadline is exceeded' do
      stub_request(:get, status_url)
        .to_return(status: 200, body: '{"data": {"status": "running"}}')
      allow(transport).to receive(:sleep)

      expect { transport.wait_for_task(context, upid, timeout: 0.05) }
        .to raise_error(Puppet::ResourceError, %r{timed out after 0\.05s})
    end

    it 'includes the last poll error when timing out on persistent poll failures' do
      stub_request(:get, status_url)
        .to_return(status: 503, body: 'Service Unavailable')
      allow(transport).to receive(:sleep)

      expect { transport.wait_for_task(context, upid, timeout: 0.05) }
        .to raise_error(Puppet::ResourceError, %r{timed out.*last poll error.*503}m)
    end

    it 'raises task failure even after transient poll errors' do
      stub_request(:get, status_url)
        .to_return(
          { status: 500, body: 'Internal Server Error' },
          { status: 200, body: '{"data": {"status": "stopped", "exitstatus": "TASK ERROR: boom"}}' },
        )
      allow(transport).to receive(:sleep)

      expect { transport.wait_for_task(context, upid, timeout: 10) }
        .to raise_error(Puppet::ResourceError, %r{PBS async task failed: TASK ERROR: boom})
    end

    context 'with task_timeout in connection_info' do
      let(:connection_info) { super().merge(task_timeout: 0.05) }

      it 'uses the configured default timeout' do
        stub_request(:get, status_url)
          .to_return(status: 200, body: '{"data": {"status": "running"}}')
        allow(transport).to receive(:sleep)

        expect { transport.wait_for_task(context, upid) }
          .to raise_error(Puppet::ResourceError, %r{timed out after 0\.05s})
      end
    end
  end

  describe 'secret protection in logs' do
    it 'never includes token_secret in any debug output' do
      stub_request(:get, "#{base_url}/config/datastore")
        .to_return(status: 200, body: '{"data": []}')

      logged = []
      allow(context).to receive(:debug) { |msg| logged << msg }

      transport.get(context, '/config/datastore')

      logged.each { |msg| expect(msg).not_to include('supersecret') }
    end

    it 'logs method and path for each request' do
      stub_request(:get, "#{base_url}/config/datastore")
        .to_return(status: 200, body: '{"data": []}')

      logged = []
      allow(context).to receive(:debug) { |msg| logged << msg }

      transport.get(context, '/config/datastore')

      expect(logged).to include(a_string_including('GET', '/config/datastore'))
    end
  end
end
