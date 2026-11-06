# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'sensitive attribute redaction' do
  # Every attribute the schemas flag as `sensitive: true`, with a usable value.
  # The final example per type asserts this stays exhaustive.
  secrets = {
    pbs_realm:               { bind_password: 'hunter2', client_key: 'hunter2' },
    pbs_remote:              { password: 'hunter2' },
    pbs_s3_endpoint:         { secret_key: 'hunter2' },
    pbs_notification_target: { smtp_password: 'hunter2', token: 'hunter2',
                               secret: [{ 'name' => 'auth', 'value' => 'aHVudGVyMg==' }] },
    pbs_user:                { password: 'hunter2' },
  }.freeze

  base = {
    pbs_realm:               { title: 'corp', realm: 'corp', type: 'ldap' },
    pbs_remote:              { title: 'offsite', name: 'offsite', host: 'pbs.example.com', userid: 'sync@pbs' },
    pbs_s3_endpoint:         { title: 'minio', id: 'minio', endpoint: 'https://s3.example.com', access_key: 'AKIA' },
    pbs_notification_target: { title: 'relay', name: 'relay', type: 'smtp' },
    pbs_user:                { title: 'svc@pbs', userid: 'svc@pbs' },
  }.freeze

  secrets.each do |type_name, attributes|
    describe type_name do
      let(:type) do
        require "puppet/type/#{type_name}"
        Puppet::Type.type(type_name)
      end

      attributes.each do |attribute, value|
        # A Resource API `sensitive: true` flag never reaches the RAL on its own,
        # which leaks the declared value into the change notice, into the report
        # event's desired_value (and so PuppetDB), and into the agent-local
        # last_run_report.yaml.
        it "marks #{attribute} sensitive on the RAL so Puppet redacts it" do
          resource = type.new(base[type_name].merge(attribute => value))
          expect(resource.parameter(attribute).sensitive).to be true
        end

        # Sensitive() in the manifest must not be what saves us: a Hiera/eyaml
        # lookup hands the type a plain String.
        it "redacts #{attribute} when it is declared as a plain value" do
          resource = type.new(base[type_name].merge(attribute => value))
          expect(resource.parameter(attribute).format('%s', value)).to eq('[redacted]')
        end
      end

      it 'leaves non-sensitive attributes unredacted' do
        resource = type.new(base[type_name])
        insensitive = type.type_definition.attributes.reject { |_name, options| options[:sensitive] }.keys
        expect(insensitive.select { |name| resource.parameter(name)&.sensitive }).to be_empty
      end

      it 'covers every attribute the schema flags as sensitive' do
        flagged = type.type_definition.attributes.select { |_name, options| options[:sensitive] == true }.keys
        expect(flagged).to match_array(attributes.keys)
      end
    end
  end
end
