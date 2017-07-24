require 'rspec'
require 'yaml'
require 'bosh/template/evaluation_context'
require 'json'
require 'deep_merge'
require 'support/yaml_eq'
require 'spec_helper'

describe 'uaa-release erb generation' do
  def perform_erb_transformation_as_yaml erb_file, manifest_file
    YAML.load(perform_erb_transformation_as_string erb_file, manifest_file)
  end

  def perform_erb_transformation_as_string erb_file, manifest_file
    binding = Bosh::Template::EvaluationContext.new(manifest_file).get_binding
    ERB.new(erb_file).result(binding)
  end

  def perform_erb_transformation_as_string_doc_mode(erb_file)
    require_relative '../docs/doc_overrides'
    the_binding = Proc.new do
      doc = 'true'
      binding()
    end.call
    ERB.new(erb_file).result(the_binding)
  end

  def read_and_parse_string_template(template, manifest, asYaml, mode = :normal)
    erbTemplate = File.read(File.join(File.dirname(__FILE__), template))

    if mode == :doc
      return perform_erb_transformation_as_string_doc_mode(erbTemplate)
    end

    if asYaml
      completedTemplate = perform_erb_transformation_as_yaml(erbTemplate, manifest)
    else
      completedTemplate = perform_erb_transformation_as_string(erbTemplate, manifest)
    end
    completedTemplate
  end

  def yml_compare(output, actual)
    expected = File.read(output)
    expect(actual).to yaml_eq(expected)
  end

  def str_compare(output, actual)
    expected = File.read(output)
    expect(actual).to eq(expected)
  end

  context 'using bosh links' do
    let(:generated_cf_manifest) { generate_cf_manifest(input, links) }
    let(:input) { 'spec/input/bosh-lite.yml' }
    let(:output_uaa) { 'spec/compare/bosh-lite-uaa.yml' }
    let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

    let(:parsed_yaml) { read_and_parse_string_template(erb_template, generated_cf_manifest, true) }

    context 'when uaadb.address is specified' do
      let(:links) {{ 'database' => {'instances' => [ {'address' => 'linkedaddress'}]}}}

      it 'takes precedence over bosh-linked address' do
        expect(parsed_yaml['database']['url']).not_to include('linkedaddress')
        expect(parsed_yaml['database']['url']).to eq 'jdbc:postgresql://10.244.0.30:5524/uaadb?ssl=true'
      end
    end

    context 'when uaadb.address missing but bosh-link address available' do
      let(:links) {{ 'database' => {'instances' => [ {'address' => 'linkedaddress'}]}}}
      before(:each) { generated_cf_manifest['properties']['uaadb']['address'] = nil }

      it 'it uses the bosh-linked address' do
        expect(parsed_yaml['database']['url']).to eq('jdbc:postgresql://linkedaddress:5524/uaadb?ssl=true')
      end
    end

    context 'when neither uaadb.address nor a bosh link are available' do
      let(:links) {{}}
      before(:each) { generated_cf_manifest['properties']['uaadb']['address'] = nil }

      it 'throws an error about the missing database configuration' do
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /Required uaadb address configuration not specified/)
      end
    end
  end

  context 'when yml files and stubs are provided' do
    let(:generated_cf_manifest) { generate_cf_manifest(input) }
    let(:as_yml) { true }
    let(:parsed_yaml) { read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml) }

    context 'for a bosh-lite.yml' do
      let(:input) { 'spec/input/bosh-lite.yml' }
      let(:output_uaa) { 'spec/compare/bosh-lite-uaa.yml' }
      let(:output_log4j) { 'spec/compare/default-log4j.properties' }

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

        it 'it matches' do
          yml_compare(output_uaa, parsed_yaml.to_yaml)
        end
      end

      context 'when log4j.properties.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/log4j.properties.erb' }
        let(:as_yml) { false }

        it 'it matches' do
          str_compare output_log4j, parsed_yaml.to_s
        end
      end
    end

    context 'for a all-properties-set.yml' do
      let(:input) { 'spec/input/all-properties-set.yml' }
      let(:output_uaa) { 'spec/compare/all-properties-set-uaa.yml' }
      let(:output_log4j) { 'spec/compare/all-properties-set-log4j.properties' }

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

        it 'it matches' do
          yml_compare(output_uaa, parsed_yaml.to_yaml)
        end
      end

      context 'when log4j.properties.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/log4j.properties.erb' }
        let(:as_yml) { false }

        it 'it matches' do
          str_compare output_log4j, parsed_yaml.to_s
        end
      end
    end

    context 'for test-defaults.yml' do
      let(:input) { 'spec/input/test-defaults.yml' }
      let(:output_uaa) { 'spec/compare/test-defaults-uaa.yml' }
      let(:output_log4j) { 'spec/compare/default-log4j.properties' }

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

        it 'it matches' do
          yml_compare output_uaa, parsed_yaml.to_yaml
        end
      end

      context 'when log4j.properties.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/log4j.properties.erb' }
        let(:as_yml) { false }

        it 'it matches' do
          str_compare output_log4j, parsed_yaml.to_s
        end
      end
    end

    context 'for deprecated-properties-still-work.yml' do
      let(:input) { 'spec/input/deprecated-properties-still-work.yml' }
      let(:output_uaa) { 'spec/compare/deprecated-properties-still-work-uaa.yml' }

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

        it 'it matches' do
          yml_compare output_uaa, parsed_yaml.to_yaml
        end
      end

    end
  end

  context 'when invalid properties are specified' do
    let!(:generated_cf_manifest) { generate_cf_manifest(input) }
    let(:as_yml) { true }
    let(:parsed_yaml) { read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml) }
    let(:input) { 'spec/input/all-properties-set.yml' }

    context 'and token format is invalid' do
      let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

      it 'raises an error' do
        generated_cf_manifest['properties']['uaa']['jwt']['refresh']['format'] = 'invalidformat';
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /uaa.jwt.refresh.format invalidformat must be one of/)
      end
    end
  end


  context 'when clients have invalid properties' do
    let!(:generated_cf_manifest) { generate_cf_manifest(input) }
    let(:as_yml) { true }
    let(:parsed_yaml) { read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml) }
    let(:input) { 'spec/input/all-properties-set.yml' }

    context 'and redirect_uri or redirect_url are set' do
      let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

      rejected_parameters = ['redirect_uri', 'redirect_url']
      rejected_parameters .each do |property|
        it "raises an error for property #{property}" do
          generated_cf_manifest['properties']['uaa']['clients']['app'][property] = 'http://some.redirect.url';
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /Invalid property: uaa.clients.app.#{property}/)
        end
      end
    end

    context 'and invalid integer values are set' do
      let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

      invalid_integers = ['access-token-validity', 'refresh-token-validity']
      invalid_integers .each do |property|
        it "raises an error for property #{property}" do
          generated_cf_manifest['properties']['uaa']['clients']['app'][property] = 'not a number';
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /Invalid number value: uaa.clients.app.#{property}/)
        end
      end
    end

    context 'and boolean integer values are set' do
      let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

      invalid_integers = ['override', 'show-on-homepage']
      invalid_integers .each do |property|
        it "raises an error for property #{property}" do
          generated_cf_manifest['properties']['uaa']['clients']['app'][property] = 'not a boolean';
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /Invalid boolean value: uaa.clients.app.#{property}/)
        end
      end
    end

    context 'and client_credentials is missing authorities' do
      let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

      it "raises an error for client_credentials" do
        generated_cf_manifest['properties']['uaa']['clients']['app']['authorized-grant-types'] = 'client_credentials';
        generated_cf_manifest['properties']['uaa']['clients']['app'].delete('authorities');
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /Missing property: uaa.clients.app.authorities/)
      end
    end

    context 'and scopes are required on a client' do
      let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }
      grant_types_requiring_secret = ['implicit',
                                      'authorization_code',
                                      'password',
                                      'urn:ietf:params:oauth:grant-type:saml2-bearer',
                                      'user_token',
                                      'urn:ietf:params:oauth:grant-type:jwt-bearer']
      grant_types_requiring_secret.each do |grant_type|
        it "raises an error for type:#{grant_type}" do
          generated_cf_manifest['properties']['uaa']['clients']['app']['authorized-grant-types'] = grant_type;
          generated_cf_manifest['properties']['uaa']['clients']['app'].delete('scope');
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /Missing property: uaa.clients.app.scope/)
        end
      end
    end


  end

  context 'when uaadb tls_enabled is set for sqlserver' do
    let(:generated_cf_manifest) { generate_cf_manifest(input)}
    let(:input) { 'spec/input/test-defaults.yml' }
    let(:output_uaa) { 'spec/compare/test-defaults-uaa.yml' }
    let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }
    let(:parsed_yaml) { read_and_parse_string_template(erb_template, generated_cf_manifest, true) }

    it 'it adds encrypt in the URL' do
      generated_cf_manifest['properties']['uaadb']['tls_enabled'] = true;
      expect(parsed_yaml['database']['url']).to eq('jdbc:sqlserver://10.244.0.30:1433;databaseName=uaadb;encrypt=true')

    end
  end

  context 'when required properties are missing in the stub' do
    let!(:generated_cf_manifest) { generate_cf_manifest(input) }
    let(:as_yml) { true }
    let(:parsed_yaml) { read_and_parse_string_template erb_template, generated_cf_manifest, as_yml }
    let(:input) { 'spec/input/all-properties-set.yml' }

    context 'the uaa.yml.erb' do
      let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }
      context 'legacy saml keys are sufficient' do
        it 'does not throw an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('keys')
          generated_cf_manifest['properties']['login']['saml'].delete('activeKeyId')
          expect {
            parsed_yaml
          }.not_to raise_error
        end
      end

      context 'login.saml.serviceProviderKey is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('keys')
          generated_cf_manifest['properties']['login']['saml'].delete('activeKeyId')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.serviceProviderKey/)
        end
      end
      context 'login.saml.serviceProviderKeyPassword is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('keys')
          generated_cf_manifest['properties']['login']['saml'].delete('activeKeyId')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKeyPassword')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.serviceProviderKeyPassword/)
        end
      end
      context 'login.saml.serviceProviderCertificate is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('keys')
          generated_cf_manifest['properties']['login']['saml'].delete('activeKeyId')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.serviceProviderCertificate/)
        end
      end

      context 'legacy saml keys are not required' do
        it 'does not throw an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKeyPassword')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          expect {
            parsed_yaml
          }.not_to raise_error
        end
      end

      context 'legacy keys not set but password is default' do
        it 'does not throw an error' do
          generated_cf_manifest['properties']['login']['saml']['serviceProviderKeyPassword'] = ''
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          expect {
            parsed_yaml
          }.not_to raise_error
        end
      end

      context 'login.saml.keys is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKeyPassword')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          generated_cf_manifest['properties']['login']['saml'].delete('keys')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.keys/)
        end
      end

      context 'login.saml.keys is empty' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKeyPassword')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          generated_cf_manifest['properties']['login']['saml']['keys'].delete('key1')
          generated_cf_manifest['properties']['login']['saml']['keys'].delete('key2')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.keys/)
        end
      end

      context 'login.saml.keys.key1 is missing certificate' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKeyPassword')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          generated_cf_manifest['properties']['login']['saml']['keys']['key1'].delete('certificate')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.keys.key1.certificate/)
        end
      end

      context 'login.saml.keys.key1 is missing passphrase' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKeyPassword')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          generated_cf_manifest['properties']['login']['saml']['keys']['key1'].delete('passphrase')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.keys.key1.passphrase/)
        end
      end

      context 'login.saml.keys.key1 is missing key' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKeyPassword')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          generated_cf_manifest['properties']['login']['saml']['keys']['key1'].delete('key')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.keys.key1.key/)
        end
      end

      context 'login.saml.activeKeyId is pointing to a non existent key' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKeyPassword')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          generated_cf_manifest['properties']['login']['saml']['activeKeyId'] = 'key3'
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.activeKeyId.*key3/)
        end
      end

      context 'login.saml.activeKeyId is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKeyPassword')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          generated_cf_manifest['properties']['login']['saml'].delete('activeKeyId')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.activeKey/)
        end
      end

      context 'authorized grant types is missing' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

        it 'raises an error' do
          generated_cf_manifest['properties']['uaa']['clients']['app'].delete('authorized-grant-types');
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /Missing property: uaa.clients.app.authorized-grant-types/)
        end
      end

      context 'client secret is missing from non implicit clients' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }
        grant_types_requiring_secret = ['client_credentials',
                                        'authorization_code',
                                        'password',
                                        'urn:ietf:params:oauth:grant-type:saml2-bearer',
                                        'user_token',
                                        'refresh_token',
                                        'urn:ietf:params:oauth:grant-type:jwt-bearer']
        grant_types_requiring_secret.each do |grant_type|
          it "raises an error for type:#{grant_type}" do
            generated_cf_manifest['properties']['uaa']['clients']['app']['authorized-grant-types'] = grant_type;
            generated_cf_manifest['properties']['uaa']['clients']['app'].delete('secret');
            expect {
              parsed_yaml
            }.to raise_error(ArgumentError, /Missing property: uaa.clients.app.secret/)
          end
        end
      end

      context 'redirect-uri is missing from required grant types' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }
        grant_types_requiring_secret = ['authorization_code', 'implicit']
        grant_types_requiring_secret.each do |grant_type|
          it "raises an error for type:#{grant_type}" do
            generated_cf_manifest['properties']['uaa']['clients']['app']['authorized-grant-types'] = grant_type;
            generated_cf_manifest['properties']['uaa']['clients']['app'].delete('redirect-uri');
            expect {
              parsed_yaml
            }.to raise_error(ArgumentError, /Missing property: uaa.clients.app.redirect-uri/)
          end
        end
      end

      invalid_redirect_uris = %w(http://* http://** http://*/** http://*/* http://**/* http://a*
          http://*.com http://*domain* http://*domain.com http://*domain/path http://local*
          *.valid.com/*/with/path** http://**/path https://*.*.*.com/*/with/path** www.*/path www.invalid.com/*/with/path**
          www.*.invalid.com/*/with/path** http://username:password@*.com http://username:password@*.com/path)

      context 'redirect-uri is invalid' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }
        grant_types_requiring_secret = ['authorization_code', 'implicit']
        invalid_redirect_uris.each do |uri| grant_types_requiring_secret.each do |grant_type|
          it "raises an error for type:#{grant_type}" do
            generated_cf_manifest['properties']['uaa']['clients']['app']['authorized-grant-types'] = grant_type
            generated_cf_manifest['properties']['uaa']['clients']['app']['redirect-uri'] = uri
            expect {
              parsed_yaml
            }.to raise_error(ArgumentError, /Client redirect-uri is invalid: uaa\.clients\.app\.redirect-uri/)
          end end
        end
      end

      context 'redirect-uri is invalid' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }
        grant_types_requiring_secret = ['authorization_code', 'implicit']
        invalid_redirect_uris.each do |uri| grant_types_requiring_secret.each do |grant_type|
          it "raises an error for type:#{grant_type}" do
            generated_cf_manifest['properties']['uaa']['clients']['app']['authorized-grant-types'] = grant_type
            generated_cf_manifest['properties']['uaa']['clients']['app']['redirect-uri'] = "http://first.com/,#{uri},https://second.com/path"
            expect {
              parsed_yaml
            }.to raise_error(ArgumentError, /Client redirect-uri is invalid: uaa\.clients\.app\.redirect-uri/)
          end end
        end
      end

    end

    context 'the uaa.yml.erb' do
      let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }
      context 'critical JWT key properties are missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['uaa']['jwt'].delete('signing_key')
          generated_cf_manifest['properties']['uaa']['jwt']['policy'].delete('active_key_id')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /active_key_id/)
        end
      end
      context 'active JWT key ID does not match do' do
        it 'throws an error' do
          generated_cf_manifest['properties']['uaa']['jwt'].delete('signing_key')
          generated_cf_manifest['properties']['uaa']['jwt']['policy']['active_key_id'] = 'key-2'
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /active_key_id mismatch/)
        end
      end
      context 'active JWT key ID is missing' do
        it 'it works because we accept legacy keys' do
          generated_cf_manifest['properties']['uaa']['jwt']['policy'].delete('active_key_id')
          expect {
            parsed_yaml
          }
        end
      end
      context 'legacy key is missing' do
        it 'it works because we have active key' do
          generated_cf_manifest['properties']['uaa']['jwt'].delete('signing_key')
          expect {
            parsed_yaml
          }
        end
      end
      context 'active signing key is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['uaa']['jwt'].delete('signing_key')
          generated_cf_manifest['properties']['uaa']['jwt']['policy']['keys']['key-1'].delete('signingKey')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /active_key_id missing signingKey/)
        end
      end

    end


  end


  def self.perform_compare(input, output_uaa, output_login, output_log4j)
    generated_cf_manifest = generate_cf_manifest(input)

    parsed_uaa_yaml = read_and_parse_string_template '../jobs/uaa/templates/uaa.yml.erb', generated_cf_manifest, true
    parsed_login_yaml =  read_and_parse_string_template '../jobs/uaa/templates/login.yml.erb', generated_cf_manifest, true
    parsed_log4j_properties =  read_and_parse_string_template '../jobs/uaa/templates/log4j.properties.erb', generated_cf_manifest, false

    doSaveOutput = ENV['TEST_SAVE'] ? ENV['TEST_SAVE'] : "false"

    if doSaveOutput == "true"
      tempDir = '/tmp/uaa-release-tests/'+input
      FileUtils.mkdir_p tempDir
      open(tempDir + '/uaa.yml', 'w') { |f|
        f.puts parsed_uaa_yaml.to_yaml(:Indent => 2, :UseHeader => true, :UseVersion => true)
      }
      open(tempDir + '/login.yml', 'w') { |f|
        f.puts parsed_login_yaml.to_yaml(:Indent => 2, :UseHeader => true, :UseVersion => true)
      }
      open(tempDir + '/log4j.properties', 'w') { |f|
        f.puts parsed_log4j_properties.to_s
      }
    end
  end

  def self.validate_required_properties input
    generated_cf_manifest = generate_cf_manifest(input)

    login_yaml_required_properties = [
      'properties.login.saml.serviceProviderKey',
      'properties.login.saml.serviceProviderKeyPassword',
      'properties.login.saml.serviceProviderCertificate'
    ]

    for addProperty in login_yaml_required_properties
      begin
        read_and_parse_string_template '../jobs/uaa/templates/login.yml.erb', generated_cf_manifest, true
        raise 'This line should not be reached'
      rescue ArgumentError
          # expected
      end
      add_param_to_hash addProperty, 'value', generated_cf_manifest
    end
    read_and_parse_string_template '../jobs/uaa/templates/login.yml.erb', generated_cf_manifest, true

    begin
      read_and_parse_string_template '../jobs/uaa/templates/uaa.yml.erb', generated_cf_manifest, true
      raise 'This line should not be reached'
    rescue ArgumentError
      # expected
    end
    add_param_to_hash 'properties.uaa.jwt.signing_key', 'value', generated_cf_manifest
    read_and_parse_string_template '../jobs/uaa/templates/uaa.yml.erb', generated_cf_manifest, true
    generated_cf_manifest['properties']['uaa']['jwt']['signing_key'] = nil
    begin
      read_and_parse_string_template '../jobs/uaa/templates/uaa.yml.erb', generated_cf_manifest, true
      raise 'This line should not be reached'
    rescue ArgumentError
      # expected
    end
    add_param_to_hash 'properties.uaa.jwt.policy.active_key_id', 'value', generated_cf_manifest
    read_and_parse_string_template '../jobs/uaa/templates/uaa.yml.erb', generated_cf_manifest, true
    generated_cf_manifest['properties']['uaa']['jwt']['policy']['active_key_id'] = nil
    begin
      read_and_parse_string_template '../jobs/uaa/templates/uaa.yml.erb', generated_cf_manifest, true
      raise 'This line should not be reached'
    rescue ArgumentError
      # expected
    end

  end

  describe 'Doc Mode' do
    let(:generated_cf_manifest) { generate_cf_manifest(input) }
    let(:as_yml) { true }
    let(:parsed_yaml) { read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml) }
    let(:input) { 'spec/input/bosh-lite.yml' }
    let(:output_uaa) { 'spec/compare/bosh-lite-uaa.yml' }
    let(:output_log4j) { 'spec/compare/default-log4j.properties' }

    before(:each) do
      @json = JSON.parse(read_and_parse_string_template('../jobs/uaa/templates/uaa.yml.erb', generated_cf_manifest, true, :doc))
    end

    it 'outputs json for one-to-one mappings' do
      expect(@json['uaa']['url']).to eq ({'*value' => '<uaa.url>', '*sources'=>{'uaa.url'=>'The base url of the UAA'}})
    end

    it 'shows named variables for .each expressions' do
      expect(@json['login']['saml']['providers']['(idpAlias)']['idpMetadata']['*value']).to eq '<login.saml.providers.(idpAlias).idpMetadata>'
    end

    it 'simplifies redundant entries' do
      expect(@json['jwt']['token']['policy']['keys']['*value']).to eq '<uaa.jwt.policy.keys>'
    end
  end
end
