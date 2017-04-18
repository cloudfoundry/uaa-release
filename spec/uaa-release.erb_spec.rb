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


  def read_and_parse_string_template(template, manifest, asYaml)
    erbTemplate = File.read(File.join(File.dirname(__FILE__), template))
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
        expect(parsed_yaml['database']['url']).to eq 'jdbc:postgresql://10.244.0.30:5524/uaadb'
      end
    end

    context 'when uaadb.address missing but bosh-link address available' do
      let(:links) {{ 'database' => {'instances' => [ {'address' => 'linkedaddress'}]}}}
      before(:each) { generated_cf_manifest['properties']['uaadb']['address'] = nil }

      it 'it uses the bosh-linked address' do
        expect(parsed_yaml['database']['url']).to eq('jdbc:postgresql://linkedaddress:5524/uaadb')
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
    let(:parsed_yaml) { read_and_parse_string_template erb_template, generated_cf_manifest, as_yml }

    context 'for a bosh-lite.yml' do
      let(:input) { 'spec/input/bosh-lite.yml' }
      let(:output_uaa) { 'spec/compare/bosh-lite-uaa.yml' }
      let(:output_login) { 'spec/compare/bosh-lite-login.yml' }
      let(:output_log4j) { 'spec/compare/default-log4j.properties' }

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

        it 'it matches' do
          yml_compare output_uaa, parsed_yaml.to_yaml
        end
      end

      context 'when login.yml.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/login.yml.erb' }

        it 'it matches' do
          yml_compare output_login, parsed_yaml.to_yaml
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
      let(:output_login) { 'spec/compare/all-properties-set-login.yml' }
      let(:output_log4j) { 'spec/compare/all-properties-set-log4j.properties' }

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

        it 'it matches' do
          yml_compare output_uaa, parsed_yaml.to_yaml
        end
      end

      context 'when login.yml.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/login.yml.erb' }

        it 'it matches' do
          yml_compare output_login, parsed_yaml.to_yaml
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
      let(:output_login) { 'spec/compare/test-defaults-login.yml' }
      let(:output_log4j) { 'spec/compare/default-log4j.properties' }

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

        it 'it matches' do
          yml_compare output_uaa, parsed_yaml.to_yaml
        end
      end

      context 'when login.yml.erb is provided' do
        let(:erb_template) { '../jobs/uaa/templates/login.yml.erb' }

        it 'it matches' do
          yml_compare output_login, parsed_yaml.to_yaml
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
  end

  context 'when invalid properites are specified' do
    let!(:generated_cf_manifest) { generate_cf_manifest(input) }
    let(:as_yml) { true }
    let(:parsed_yaml) { read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml) }
    let(:input) { 'spec/input/all-properties-set.yml' }

    context 'for uaa.yml.erb' do
      let(:erb_template) { '../jobs/uaa/templates/uaa.yml.erb' }

      it 'raises an error' do
        generated_cf_manifest['properties']['uaa']['jwt']['refresh']['format'] = 'invalidformat';
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /uaa.jwt.refresh.format invalidformat must be one of/)
      end
    end
  end
  
  context 'when required properties are missing in the stub' do
    let!(:generated_cf_manifest) { generate_cf_manifest(input) }
    let(:as_yml) { true }
    let(:parsed_yaml) { read_and_parse_string_template erb_template, generated_cf_manifest, as_yml }
    let(:input) { 'spec/input/all-properties-set.yml' }

    context 'the login.yml.erb' do
      let(:erb_template) { '../jobs/uaa/templates/login.yml.erb' }
      context 'login.saml.serviceProviderKey is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKey')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.serviceProviderKey/)
        end
      end
      context 'login.saml.serviceProviderKeyPassword is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderKeyPassword')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.serviceProviderKeyPassword/)
        end
      end
      context 'login.saml.serviceProviderCertificate is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('serviceProviderCertificate')
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.saml.serviceProviderCertificate/)
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

    # it "uaa.yml for "+input+" must match" do
    #   expected = File.read(output_uaa)
    #   actual = parsed_uaa_yaml.to_yaml
    #   expect(actual).to yaml_eq(expected)
    # end
    # it "login.yml for "+input+" must match" do
    #   expected = File.read(output_login)
    #   actual = parsed_login_yaml.to_yaml
    #   expect(actual).to yaml_eq(expected)
    # end
    # it "log4j.properties for "+input+" must match" do
    #   expected = File.read(output_log4j)
    #   actual = parsed_log4j_properties.to_s
    #   expect(actual).to eq(expected)
    # end

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

  # validate_required_properties 'spec/input/missing-required-properties.yml'
  # perform_compare 'spec/input/bosh-lite.yml', 'spec/compare/bosh-lite-uaa.yml', 'spec/compare/bosh-lite-login.yml', 'spec/compare/default-log4j.properties'
  # perform_compare 'spec/input/all-properties-set.yml', 'spec/compare/all-properties-set-uaa.yml', 'spec/compare/all-properties-set-login.yml', 'spec/compare/all-properties-set-log4j.properties'
  # perform_compare 'spec/input/test-defaults.yml', 'spec/compare/test-defaults-uaa.yml', 'spec/compare/test-defaults-login.yml', 'spec/compare/default-log4j.properties'
end
