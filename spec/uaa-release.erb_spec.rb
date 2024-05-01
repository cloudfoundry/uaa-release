require 'rspec'
require 'yaml'
require 'bosh/template/evaluation_context'
require 'json'
require 'support/yaml_eq'
require 'spec_helper'

class MockDNSEncoder
  def encode_query(full_criteria, use_short_dns)
    return 'linkedaddress'
  end
end

describe 'uaa-release erb generation' do
  def perform_erb_transformation_as_yaml(erb_file, manifest_file)
    YAML.load(perform_erb_transformation_as_string(erb_file, manifest_file))
  end

  def perform_erb_transformation_as_string(erb_file, manifest_file)

    binding = Bosh::Template::EvaluationContext.new(manifest_file, MockDNSEncoder.new).get_binding
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
    let(:generated_cf_manifest) {generate_cf_manifest(input, links)}
    let(:input) {'spec/input/bosh-lite.yml'}
    let(:output_uaa) {'spec/compare/bosh-lite-uaa.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, true)}

    context 'when uaadb.address is specified' do
      let(:links) do
        {
            'database' => {
                'instances' => [],
                'properties' => {'database' => {'address' => 'linkedaddress'}}
            }
        }
      end

      it 'takes precedence over bosh-linked address' do
        expect(parsed_yaml['database']['url']).not_to include('linkedaddress')
        expect(parsed_yaml['database']['url']).to eq 'jdbc:postgresql://10.244.0.30:5524/uaadb?sslmode=verify-full&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory'
      end
    end

    context 'when uaadb.address missing but bosh-link address available' do
      let(:links) do
        {
            'database' => {
                'instances' => [],
                'properties' => {'database' => {'address' => 'linkedaddress'}}
            }
        }
      end

      before(:each) {generated_cf_manifest['properties']['uaadb']['address'] = nil}

      it 'uses the bosh-linked address' do
        expect(parsed_yaml['database']['url']).to eq('jdbc:postgresql://linkedaddress:5524/uaadb?sslmode=verify-full&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory')
      end
    end

    context 'when neither uaadb.address nor a bosh link are available' do
      let(:links) {{}}
      before(:each) {generated_cf_manifest['properties']['uaadb']['address'] = nil}

      it 'throws an error about the missing database configuration' do
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /Required uaadb address configuration not specified/)
      end
    end
  end

  context 'when yml files and stubs are provided' do
    let(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:as_yml) {true}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml)}

    context 'for a bosh-lite.yml' do
      let(:input) {'spec/input/bosh-lite.yml'}
      let(:output_uaa) {'spec/compare/bosh-lite-uaa.yml'}
      let(:output_log4j2) {'spec/compare/default-log4j2.properties'}

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

        it 'matches' do
          yml_compare(output_uaa, parsed_yaml.to_yaml)
        end
      end

      context 'when log4j2.properties.erb is provided' do
        let(:erb_template) {'../jobs/uaa/templates/config/log4j2.properties.erb'}
        let(:as_yml) {false}

        it 'matches' do
          str_compare output_log4j2, parsed_yaml.to_s
        end
      end
    end

    context 'for a all-properties-set.yml' do
      let(:input) {'spec/input/all-properties-set.yml'}
      let(:output_uaa) {'spec/compare/all-properties-set-uaa.yml'}
      let(:output_log4j2) {'spec/compare/all-properties-set-log4j2.properties'}

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

        it 'matches' do
          yml_compare(output_uaa, parsed_yaml.to_yaml)
        end
      end

      context 'when log4j2.properties.erb is provided' do
        let(:erb_template) {'../jobs/uaa/templates/config/log4j2.properties.erb'}
        let(:as_yml) {false}

        it 'matches' do
          str_compare output_log4j2, parsed_yaml.to_s
        end
      end
    end

    context 'for test-defaults.yml' do
      let(:input) {'spec/input/test-defaults.yml'}
      let(:output_uaa) {'spec/compare/test-defaults-uaa.yml'}
      let(:output_log4j2) {'spec/compare/default-log4j2.properties'}

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

        it 'matches' do
          yml_compare output_uaa, parsed_yaml.to_yaml
        end
      end

      context 'when log4j2.properties.erb is provided' do
        let(:erb_template) {'../jobs/uaa/templates/config/log4j2.properties.erb'}
        let(:as_yml) {false}

        it 'matches' do
          str_compare output_log4j2, parsed_yaml.to_s
        end
      end
    end

    context 'for deprecated-properties-still-work.yml' do
      let(:input) {'spec/input/deprecated-properties-still-work.yml'}
      let(:output_uaa) {'spec/compare/deprecated-properties-still-work-uaa.yml'}

      context 'when uaa.yml.erb is provided' do
        let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

        it 'matches' do
          yml_compare output_uaa, parsed_yaml.to_yaml
        end
      end

    end
  end

  context 'health_check' do
    let(:input) {'spec/input/bosh-lite.yml'}
    let!(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, false)}
    let(:output_health_check) {'spec/compare/health-check'}
    let(:erb_template) {'../jobs/uaa/templates/bin/health_check.erb'}

    before(:each) do
      generated_cf_manifest['properties']['uaa']['ssl']['port'] = 9090
    end

    it 'correctly generates dns health check with https port' do
      str_compare output_health_check, parsed_yaml.to_s
    end
  end

  context 'when invalid properties are specified' do
    let!(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:as_yml) {true}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml)}
    let(:input) {'spec/input/all-properties-set.yml'}

    context 'and token format is invalid' do
      let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

      it 'raises an error' do
        generated_cf_manifest['properties']['uaa']['jwt']['refresh']['format'] = 'invalidformat';
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /uaa.jwt.refresh.format invalidformat must be one of/)
      end
    end

    context 'release_level_backup' do
      let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

      it 'raises an error if set' do
        generated_cf_manifest['properties']['release_level_backup'] = true
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /DEPRECATED: release_level_backup in the uaa job should no longer be used. Please set the corresponding release_level_backup property in the bbr-uaadb job instead/)
      end
    end
  end

  context 'when branding consent is specified for default zone' do
    let!(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:as_yml) {true}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml)}
    let(:input) {'spec/input/all-properties-set.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

    context 'and only consent text is provided' do
      it 'does not raise an error' do
        generated_cf_manifest['properties']['login']['branding']['consent'].delete('link')
        parsed_yaml
      end
    end

    context 'and only consent link is provided' do
      it 'raises an error' do
        generated_cf_manifest['properties']['login']['branding']['consent'].delete('text')
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /login.branding.consent.text must also be provided if specifying login.branding.consent.link/)
      end
    end

    context 'and consent link is a valid URI' do
      valid_uris = ['https://example.com',
                    'https://example.com/',
                    'http://example.com/',
                    'ftp://example.com/',
                    'https://example.com?',
                    'https://example.com?a=b',
                    'https://example.com?a=b&c=d',
                    'https://example.com/?a=b',
                    'https://example.com/some/path',
                    'https://example.com#fragment',
                    'https://example.io',
                    'https://example.longtld',
                    'https://subdomain.example.com',
                    'https://subdomain.example.com',
                    'https://example.co.uk',
                    'https://example',
                    'http://127.0.0.1',
                    'http://224.1.1.1 '
      ]

      valid_uris.each do |url|
        it 'does not raise an error' do
          generated_cf_manifest['properties']['login']['branding']['consent']['link'] = url
          parsed_yaml
        end
      end
    end

    context 'and consent link is not a valid URI' do
      invalid_uris = ['www.example.com',
                      'gabr://example.com',
                      'example',
                      'example.com',
                      'example.com:666',
                      '// ',
                      '//a',
                      '///a ',
                      '///',
                      'rdar://1234',
                      'h://test ',
                      ':// should fail',
                      'ftps://foo.bar/',
      ]

      invalid_uris.each do |url|
        it 'raises an error' do
          generated_cf_manifest['properties']['login']['branding']['consent']['link'] = url
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /login.branding.consent.link value .* is not a valid uri/)
        end
      end
    end
  end

  context 'login.saml boolean properties' do
    let!(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:as_yml) {true}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml)}
    let(:input) {'spec/input/all-properties-set.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

    props = ['signMetaData', 'signRequest']

    context 'when the properties are true' do
      it 'adds the properties' do
        props.each { |p| generated_cf_manifest['properties']['login']['saml'][p] = true }
        props.each { |p| expect(parsed_yaml['login']['saml'][p]).to eq(true) }
      end
    end

    context 'when the properties are false' do
      it 'adds the properties' do
        props.each { |p| generated_cf_manifest['properties']['login']['saml'][p] = false }
        props.each { |p| expect(parsed_yaml['login']['saml'][p]).to eq(false) }
      end
    end

    context 'when the properties do not exist' do
      it 'does not add the properties' do
        props.each { |p| generated_cf_manifest['properties']['login']['saml'].delete(p) }
        props.each { |p| expect(parsed_yaml['login']['saml'][p]).to eq(nil) }
      end
    end
  end

  context 'when login banner is specified' do
    let!(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:as_yml) {true}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml)}
    let(:input) {'spec/input/all-properties-set.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

    context 'and text color is in hex format' do
      it 'does not raise an error' do
        generated_cf_manifest['properties']['login']['branding']['banner']['textColor'] = '#ab9';
        parsed_yaml
      end
    end

    context 'and background color is in hex format' do
      it 'does not raise an error' do
        generated_cf_manifest['properties']['login']['branding']['banner']['backgroundColor'] = '#ab9';
        parsed_yaml
      end
    end

    context 'and text color is not in hex format' do
      it 'raises an error' do
        generated_cf_manifest['properties']['login']['branding']['banner']['textColor'] = '#FFFGFF';
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /login.branding.banner.textColor value #FFFGFF is not a valid hex code/)
      end
    end

    context 'and background color is not in hex format' do
      it 'raises an error' do
        generated_cf_manifest['properties']['login']['branding']['banner']['backgroundColor'] = 'FFFEFF';
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /login.branding.banner.backgroundColor value FFFEFF is not a valid hex code/)
      end
    end

    context 'and link is a valid URI' do
      valid_uris = ['https://example.com',
                    'https://example.com/',
                    'http://example.com/',
                    'ftp://example.com/',
                    'https://example.com?',
                    'https://example.com?a=b',
                    'https://example.com?a=b&c=d',
                    'https://example.com/?a=b',
                    'https://example.com/some/path',
                    'https://example.com#fragment',
                    'https://example.io',
                    'https://example.longtld',
                    'https://subdomain.example.com',
                    'https://subdomain.example.com',
                    'https://example.co.uk',
                    'https://example',
                    'http://127.0.0.1',
                    'http://224.1.1.1 '
      ]

      valid_uris.each do |url|
        it 'does not raise' do
          generated_cf_manifest['properties']['login']['branding']['banner']['link'] = url;
          parsed_yaml
        end
      end
    end

    context 'and link is not a valid URI' do
      invalid_uris = ['www.example.com',
                      'gabr://example.com',
                      'example',
                      'example.com',
                      'example.com:666',
                      '// ',
                      '//a',
                      '///a ',
                      '///',
                      'rdar://1234',
                      'h://test ',
                      ':// should fail',
                      'ftps://foo.bar/',
      ]

      invalid_uris.each do |url|
        it 'raises an error' do
          generated_cf_manifest['properties']['login']['branding']['banner']['link'] = url;
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError)
        end
      end
    end
  end

  context 'when clients have invalid properties' do
    let!(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:as_yml) {true}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml)}
    let(:input) {'spec/input/all-properties-set.yml'}

    context 'and redirect_uri or redirect_url are set' do
      let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

      rejected_parameters = ['redirect_uri', 'redirect_url']
      rejected_parameters.each do |property|
        it "raises an error for property #{property}" do
          generated_cf_manifest['properties']['uaa']['clients']['app'][property] = 'http://some.redirect.url';
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /Invalid property: uaa.clients.app.#{property}/)
        end
      end
    end

    context 'and invalid integer values are set' do
      let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

      invalid_integers = ['access-token-validity', 'refresh-token-validity']
      invalid_integers.each do |property|
        it "raises an error for property #{property}" do
          generated_cf_manifest['properties']['uaa']['clients']['app'][property] = 'not a number';
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /Invalid number value: uaa.clients.app.#{property}/)
        end
      end
    end

    context 'and boolean integer values are set' do
      let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

      invalid_integers = ['override', 'show-on-homepage']
      invalid_integers.each do |property|
        it "raises an error for property #{property}" do
          generated_cf_manifest['properties']['uaa']['clients']['app'][property] = 'not a boolean';
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /Invalid boolean value: uaa.clients.app.#{property}/)
        end
      end
    end

    context 'and client_credentials is missing authorities' do
      let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

      it 'raises an error for client_credentials' do
        generated_cf_manifest['properties']['uaa']['clients']['app']['authorized-grant-types'] = 'client_credentials';
        generated_cf_manifest['properties']['uaa']['clients']['app'].delete('authorities');
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /Missing property: uaa.clients.app.authorities/)
      end
    end

    context 'and scopes are required on a client' do
      let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
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
          }.to raise_error(ArgumentError, /Missing property: uaa.clients.app.scope or uaa.clients.app.scopes/)
        end
      end
    end

    context "and either 'scope' string or 'scopes' list is required on a client" do
      let(:erb_template) { '../jobs/uaa/templates/config/uaa.yml.erb' }
      grant_types_requiring_secret = ['implicit',
                                      'authorization_code',
                                      'password',
                                      'urn:ietf:params:oauth:grant-type:saml2-bearer',
                                      'user_token',
                                      'urn:ietf:params:oauth:grant-type:jwt-bearer']
      grant_types_requiring_secret.each do |grant_type|
        it "raises an error for type:#{grant_type}" do
          generated_cf_manifest['properties']['uaa']['clients']['app-with-yaml-scopes']['authorized-grant-types'] = grant_type;
          generated_cf_manifest['properties']['uaa']['clients']['app-with-yaml-scopes'].delete('scopes');
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /Missing property: uaa.clients.app-with-yaml-scopes.scope or uaa.clients.app-with-yaml-scopes.scopes/)
        end
      end
    end


  end

  context 'when ldap is not enabled' do
    let(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:input) {'spec/input/all-properties-set.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, true)}

    context 'ldap override flag present when ldap.enabled is false' do
      it 'places property ldap.override in uaa.yml' do
        generated_cf_manifest['properties']['uaa']['ldap']['enabled'] = false
        generated_cf_manifest['properties']['uaa']['ldap']['override'] = false
        expect(parsed_yaml['ldap']['override']).to eq(false)
      end
    end

  end

  describe 'uaadb.db_scheme' do
    let(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:input) {'spec/input/test-defaults.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, true)}

    before do
      generated_cf_manifest['properties']['uaadb']['port'] = '7676'
      generated_cf_manifest['properties']['uaadb']['address'] = 'my-hostname'
    end

    context 'when mysql' do
      before do
        generated_cf_manifest['properties']['uaadb']['db_scheme'] = 'mysql'
      end

      it 'should correctly render a mysql JDBC connection string' do
        expect(parsed_yaml['database']['url']).to eq('jdbc:mysql://my-hostname:7676/uaadb?useSSL=true')
      end
    end

    context 'when postgres' do
      before do
        generated_cf_manifest['properties']['uaadb']['db_scheme'] = 'postgres'
      end

      it 'should correctly render a postgresql JDBC connection string' do
        expect(parsed_yaml['database']['url']).to eq('jdbc:postgresql://my-hostname:7676/uaadb?sslmode=verify-full&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory')
      end
    end

    context 'when postgresql' do
      before do
        generated_cf_manifest['properties']['uaadb']['db_scheme'] = 'postgresql'
      end

      it 'should correctly render a postgresql JDBC connection string' do
        expect(parsed_yaml['database']['url']).to eq('jdbc:postgresql://my-hostname:7676/uaadb?sslmode=verify-full&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory')
      end
    end

    context 'when unsupported db_scheme' do
      before do
        generated_cf_manifest['properties']['uaadb']['db_scheme'] = 'foobardb'
      end

      it 'should tell the operator that only mysql and postgres are supported' do
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, 'Please select either mysql or postgres for uaadb.db_scheme')
      end
    end
  end

  describe 'uaa.ssl.port' do
    let(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:input) {'spec/input/test-defaults.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, true)}

    context 'when set' do
      before do
        generated_cf_manifest['properties']['uaa']['ssl']['port'] = '9897'
      end

      it 'renders the port into uaa.yml' do
        expect(parsed_yaml['https_port']).to eq('9897')
      end
    end
  end

  describe 'uaa.client.redirect_uri.matching_mode' do
    let(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:input) {'spec/input/test-defaults.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, true)}

    context 'when set to legacy' do
      before do
        generated_cf_manifest['properties']['uaa']['client']['redirect_uri']['matching_mode'] = 'legacy'
      end

      it 'renders into uaa.yml' do
        expect(parsed_yaml['uaa']['oauth']['redirect_uri']['allow_unsafe_matching']).to eq(true)
      end
    end

    context 'when set to exact' do
      before do
        generated_cf_manifest['properties']['uaa']['client']['redirect_uri']['matching_mode'] = 'exact'
      end

      it 'renders into uaa.yml' do
        expect(parsed_yaml['uaa']['oauth']['redirect_uri']['allow_unsafe_matching']).to eq(false)
      end
    end

    context 'when set to anything other than legacy or exact' do
      before do
        generated_cf_manifest['properties']['uaa']['client']['redirect_uri']['matching_mode'] = 'foo'
      end

      it 'raises an error' do
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, 'Invalid value for uaa.client.redirect_uri.matching_mode. Valid options are legacy or exact.')
      end
    end

    context 'when not set by the user' do
      it 'defaults to true' do
        expect(parsed_yaml['uaa']['oauth']['redirect_uri']['allow_unsafe_matching']).to eq(true)
      end
    end
  end

  describe 'uaadb.tls' do
    let(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:input) {'spec/input/test-defaults.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, true)}

    context 'when set to an invalid value' do
      before do
        generated_cf_manifest['properties']['uaadb']['tls'] = 'foobar is invalid'
      end

      it 'raises an error' do
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, 'Invalid value for uaadb.tls. Valid options are enabled, enabled_skip_hostname_validation, enabled_skip_all_validation, disabled.')
      end
    end

    context 'for mysql' do
      before do
        generated_cf_manifest['properties']['uaadb']['db_scheme'] = 'mysql'
        generated_cf_manifest['properties']['uaadb']['port'] = '9999'
      end

      context 'with tls enabled' do
        before do
          generated_cf_manifest['properties']['uaadb']['tls'] = 'enabled'
        end

        it 'adds useSSL=true to the URL' do
          expect(parsed_yaml['database']['url']).to eq('jdbc:mysql://10.244.0.30:9999/uaadb?useSSL=true')
        end

        context 'with uaadb.tls_protocols' do
          before do
            generated_cf_manifest['properties']['uaadb']['tls_protocols'] = 'someProtocol'
          end

          it 'adds the protocol to the URL' do
            expect(parsed_yaml['database']['url']).to eq('jdbc:mysql://10.244.0.30:9999/uaadb?useSSL=true&enabledSslProtocolSuites=someProtocol')
          end
        end
      end

      context 'with tls disabled' do
        before do
          generated_cf_manifest['properties']['uaadb']['tls'] = 'disabled'
        end

        it 'adds useSSL=false to the URL' do
          expect(parsed_yaml['database']['url']).to eq('jdbc:mysql://10.244.0.30:9999/uaadb?useSSL=false')
        end

        context 'with uaadb.tls_protocols' do
          before do
            generated_cf_manifest['properties']['uaadb']['tls_protocols'] = 'someProtocol'
          end

          it 'does not change the URL' do
            expect(parsed_yaml['database']['url']).to eq('jdbc:mysql://10.244.0.30:9999/uaadb?useSSL=false')
          end
        end
      end

      context 'with tls enabled_skip_all_validation' do
        before do
          generated_cf_manifest['properties']['uaadb']['tls'] = 'enabled_skip_all_validation'
        end

        it 'adds useSSL=false and trustServerCertificate=true to the URL' do
          expect(parsed_yaml['database']['url']).to eq('jdbc:mysql://10.244.0.30:9999/uaadb?useSSL=true&trustServerCertificate=true')
        end

        context 'with uaadb.tls_protocols' do
          before do
            generated_cf_manifest['properties']['uaadb']['tls_protocols'] = 'someProtocol'
          end

          it 'adds the protocol to the URL' do
            expect(parsed_yaml['database']['url']).to eq('jdbc:mysql://10.244.0.30:9999/uaadb?useSSL=true&trustServerCertificate=true&enabledSslProtocolSuites=someProtocol')
          end
        end
      end

      context 'with tls enabled_skip_hostname_validation' do
        before do
          generated_cf_manifest['properties']['uaadb']['tls'] = 'enabled_skip_hostname_validation'
        end

        it 'adds useSSL=true and disableSslHostnameVerification=true to the URL' do
          expect(parsed_yaml['database']['url']).to eq('jdbc:mysql://10.244.0.30:9999/uaadb?useSSL=true&disableSslHostnameVerification=true')
        end

        context 'with uaadb.tls_protocols' do
          before do
            generated_cf_manifest['properties']['uaadb']['tls_protocols'] = 'someProtocol'
          end

          it 'adds the protocol to the URL' do
            expect(parsed_yaml['database']['url']).to eq('jdbc:mysql://10.244.0.30:9999/uaadb?useSSL=true&disableSslHostnameVerification=true&enabledSslProtocolSuites=someProtocol')
          end
        end
      end
    end

    context 'for postgres' do
      before do
        generated_cf_manifest['properties']['uaadb']['db_scheme'] = 'postgres'
        generated_cf_manifest['properties']['uaadb']['port'] = '7777'
      end

      context 'with tls enabled' do
        before do
          generated_cf_manifest['properties']['uaadb']['tls'] = 'enabled'
        end

        it 'adds sslmode=verify-full to the URL' do
          expect(parsed_yaml['database']['url']).to eq('jdbc:postgresql://10.244.0.30:7777/uaadb?sslmode=verify-full&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory')
        end
      end

      context 'with tls disabled' do
        before do
          generated_cf_manifest['properties']['uaadb']['tls'] = 'disabled'
        end

        it 'adds sslmode=disable to the URL' do
          expect(parsed_yaml['database']['url']).to eq('jdbc:postgresql://10.244.0.30:7777/uaadb?sslmode=disable')
        end
      end

      context 'with tls enabled_skip_all_validation' do
        before do
          generated_cf_manifest['properties']['uaadb']['tls'] = 'enabled_skip_all_validation'
        end

        it 'adds sslmode=require to the URL' do
          expect(parsed_yaml['database']['url']).to eq('jdbc:postgresql://10.244.0.30:7777/uaadb?sslmode=require')
        end
      end

      context 'with tls enabled_skip_hostname_validation' do
        before do
          generated_cf_manifest['properties']['uaadb']['tls'] = 'enabled_skip_hostname_validation'
        end

        it 'adds sslmode=verify-ca to the URL' do
          expect(parsed_yaml['database']['url']).to eq('jdbc:postgresql://10.244.0.30:7777/uaadb?sslmode=verify-ca&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory')
        end
      end
    end

    describe 'the removed uaadb.tls_enabled and uaadb.skip_ssl_validation properties' do
      context 'when uaadb.tls_enabled is set' do
        before do
          generated_cf_manifest['properties']['uaadb']['tls_enabled'] = false
        end

        it 'raises an error to prevent an upgrade from accidentally changing the deployment from non-TLS to TLS' do
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, 'uaadb.tls_enabled is no longer supported. Please use uaadb.tls instead.')
        end
      end

      context 'when uaadb.skip_ssl_validation is set' do
        before do
          generated_cf_manifest['properties']['uaadb']['skip_ssl_validation'] = true
        end

        it 'raises an error to prevent an upgrade from accidentally changing from skipping validation to not skipping' do
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, 'uaadb.skip_ssl_validation is no longer supported. Please use uaadb.tls instead.')
        end
      end
    end
  end

  context 'when required properties are missing in the stub' do
    let!(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:as_yml) {true}
    let(:parsed_yaml) {read_and_parse_string_template erb_template, generated_cf_manifest, as_yml}
    let(:input) {'spec/input/all-properties-set.yml'}

    context 'the uaa.yml.erb' do
      let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
      context 'legacy saml keys are sufficient' do
        it 'does not throw an error' do
          generated_cf_manifest['properties']['login']['saml'].delete('keys')
          generated_cf_manifest['properties']['login']['saml'].delete('activeKeyId')
          expect {
            parsed_yaml
          }.not_to raise_error
        end
      end

      context 'encryption.active_key_label is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['encryption'].delete('active_key_label')

          expect {
            parsed_yaml
          }.to raise_error(Bosh::Template::UnknownProperty, /encryption.active_key_label/)
        end
      end

      context 'a single encryption passphrase is less than 8 characters long' do
        it 'throws an error' do
          generated_cf_manifest['properties']['encryption']['encryption_keys'].first['passphrase'] = '1234567'

          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /The required length of the encryption passphrases for \["key1"\] need to be at least 8 characters long./)
        end
      end

      context 'multiple encryption passphrases are less than 8 characters long' do
        it 'throws an error' do
          generated_cf_manifest['properties']['encryption']['encryption_keys'] << {'label' => 'key3', 'passphrase' => '87654321'}
          generated_cf_manifest['properties']['encryption']['encryption_keys'] << {'label' => 'key2', 'passphrase' => '7654321'}
          generated_cf_manifest['properties']['encryption']['encryption_keys'].first['passphrase'] = '1234567'

          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /The required length of the encryption passphrases for \["key1", "key2"\] need to be at least 8 characters long./)
        end
      end

      context 'a valid key label does not exist' do
        it 'throws an error' do
          generated_cf_manifest['properties']['encryption']['active_key_label'] = 'key-does-not-exist'

          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /UAA cannot be started as encryption key passphrase for uaa.encryption.encryption_keys\/\[label=key-does-not-exist\] is undefined/)
        end
      end

      context 'single encryption key is missing a passphrase' do
        it 'throws an error' do
          generated_cf_manifest['properties']['encryption']['encryption_keys'] << {'label' => 'key42', 'passphrase' => nil}

          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /UAA cannot be started as encryption key passphrase for uaa.encryption.encryption_keys\/\[label=key42\] is undefined/)
        end
      end

      context 'multiple encryption keys are missing a passphrase' do
        it 'throws an error' do
          generated_cf_manifest['properties']['encryption']['encryption_keys'] << {'label' => 'key2', 'passphrase' => nil}
          generated_cf_manifest['properties']['encryption']['encryption_keys'] << {'label' => 'key3', 'passphrase' => ''}

          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /UAA cannot be started as encryption key passphrase for uaa.encryption.encryption_keys\/\[label=key2, label=key3\] is undefined/)
        end
      end

      context 'multiple encryption keys with the same key label' do
        it 'throws an error' do
          generated_cf_manifest['properties']['encryption']['encryption_keys'] << {'label' => 'key1', 'passphrase' => '987654321'}

          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /UAA cannot be started as multiple keys have the same label in uaa.encryption.encryption_keys\/\[label=key1\]/)
        end
      end

      context 'when active key is set without any encryption keys defined' do
        it 'throws an error' do
          generated_cf_manifest['properties']['encryption']['encryption_keys'] = []

          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /UAA cannot be started as encryption key passphrase for uaa.encryption.encryption_keys\/\[label=key1\] is undefined/)
        end
      end

      context 'when the active key is set to an empty string' do
        it 'throws an error' do
          generated_cf_manifest['properties']['encryption']['active_key_label'] = ''

          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, 'UAA cannot be started without encryption key value uaa.encryption.active_key_label')
        end
      end

      context 'encryption.encryption_keys is missing' do
        it 'throws an error' do
          generated_cf_manifest['properties']['encryption'].delete('encryption_keys')

          expect {
            parsed_yaml
          }.to raise_error(Bosh::Template::UnknownProperty, /encryption.encryption_keys/)
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
        let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}

        it 'raises an error' do
          generated_cf_manifest['properties']['uaa']['clients']['app'].delete('authorized-grant-types');
          expect {
            parsed_yaml
          }.to raise_error(ArgumentError, /Missing property: uaa.clients.app.authorized-grant-types/)
        end
      end

      context 'client secret is missing from non implicit clients' do
        let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
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
        let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
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
          *.valid.cloudfoundry.org/*/with/path** http://**/path https://*.*.*.com/*/with/path** www.*/path www.invalid.cloudfoundry.org/*/with/path**
          www.*.invalid.cloudfoundry.org/*/with/path** http://username:password@*.com http://username:password@*.com/path)

      context 'redirect-uri is invalid' do
        let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
        grant_types_requiring_secret = ['authorization_code', 'implicit']
        invalid_redirect_uris.each do |uri|
          grant_types_requiring_secret.each do |grant_type|
            it "raises an error for type:#{grant_type}" do
              generated_cf_manifest['properties']['uaa']['clients']['app']['authorized-grant-types'] = grant_type
              generated_cf_manifest['properties']['uaa']['clients']['app']['redirect-uri'] = uri
              expect {
                parsed_yaml
              }.to raise_error(ArgumentError, /Client redirect-uri is invalid: uaa\.clients\.app\.redirect-uri/)
            end
          end
        end
      end

      context 'redirect-uri is invalid' do
        let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
        grant_types_requiring_secret = ['authorization_code', 'implicit']
        invalid_redirect_uris.each do |uri|
          grant_types_requiring_secret.each do |grant_type|
            it "raises an error for type:#{grant_type}" do
              generated_cf_manifest['properties']['uaa']['clients']['app']['authorized-grant-types'] = grant_type
              generated_cf_manifest['properties']['uaa']['clients']['app']['redirect-uri'] = "http://first.com/,#{uri},https://second.com/path"
              expect {
                parsed_yaml
              }.to raise_error(ArgumentError, /Client redirect-uri is invalid: uaa\.clients\.app\.redirect-uri/)
            end
          end
        end
      end

    end

    context 'the uaa.yml.erb' do
      let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
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
        it 'works because we accept legacy keys' do
          generated_cf_manifest['properties']['uaa']['jwt']['policy'].delete('active_key_id')
          expect {
            parsed_yaml
          }
        end
      end
      context 'legacy key is missing' do
        it 'works because we have active key' do
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

  describe 'uaa.yml for DB TLS tests' do
    let!(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
    let(:parsed_yaml) {read_and_parse_string_template erb_template, generated_cf_manifest, true}
    let(:input) {'spec/input/database-tls-tests.yml'}
    let(:tempDir) {'/tmp/uaa-release-tests/'}

    before(:each) {
      generated_cf_manifest['properties']['uaadb']['tls'] = 'enabled'
    }

    context 'is generated for MySQL' do
      let(:filename) {'mysql'}
      it 'and writes the file' do
        generated_cf_manifest['properties']['uaadb']['db_scheme'] = 'mysql'
        generated_cf_manifest['properties']['uaadb']['port'] = '3306'
        generated_cf_manifest['properties']['uaadb']['roles'][0]['password'] = 'changeme'

        FileUtils.mkdir_p tempDir
        open(tempDir + '/' + filename + '.yml', 'w') {|f|
          f.puts parsed_yaml.to_yaml(:Indent => 2, :UseHeader => true, :UseVersion => true)
        }
      end
    end

    context 'is generated for PostgreSQL' do
      let(:filename) {'postgresql'}
      it 'and writes the file' do
        generated_cf_manifest['properties']['uaadb']['db_scheme'] = 'postgres'
        generated_cf_manifest['properties']['uaadb']['port'] = '5432'
        generated_cf_manifest['properties']['uaadb']['roles'][0]['password'] = 'changeme'
        FileUtils.mkdir_p tempDir
        open(tempDir + '/' + filename + '.yml', 'w') {|f|
          f.puts parsed_yaml.to_yaml(:Indent => 2, :UseHeader => true, :UseVersion => true)
        }
      end
    end
  end


  describe 'uaa.servlet.session-store' do
    let(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:input) {'spec/input/test-defaults.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, true)}

    context 'by default' do
      it 'renders the session-store into uaa.yml' do
        expect(parsed_yaml['servlet']['session-store']).to eq('memory')
      end
    end

    context 'when set to database' do
      before do
        generated_cf_manifest['properties']['uaa']['servlet']['session-store'] = 'database'
      end

      it 'renders the session-store into uaa.yml' do
        expect(parsed_yaml['servlet']['session-store']).to eq('database')
      end
    end

    context 'when set to an invalid value' do
      it 'raises an error' do
        generated_cf_manifest['properties']['uaa']['servlet']['session-store'] = 'foo'
        expect {
          parsed_yaml
        }.to raise_error(ArgumentError, /uaa.servlet.session-store invalid. Must be one of /)
      end
    end
  end

  describe 'uaa.authentication.enable_uri_encoding_compatibility_mode' do
    let(:input) {'spec/input/test-defaults.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
    let(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, true)}

    context 'by default' do
      it 'is false in uaa.yml' do
        expect(parsed_yaml['authentication']['enableUriEncodingCompatibilityMode']).to eq(false)
      end
    end

    context 'when configured to true' do
      before do
        generated_cf_manifest['properties']['uaa']['authentication']['enable_uri_encoding_compatibility_mode'] = true
      end

      it 'is false in uaa.yml' do
        expect(parsed_yaml['authentication']['enableUriEncodingCompatibilityMode']).to eq(true)
      end
    end
  end

  describe 'uaa.cors.enforce_system_zone_policy_in_all_zones' do
    let(:input) {'spec/input/test-defaults.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
    let(:generated_cf_manifest) {generate_cf_manifest(input)}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, true)}

    context 'by default' do
      it 'is true in uaa.yml' do
        expect(parsed_yaml['cors']['enforceSystemZonePolicyInAllZones']).to eq(true)
      end
    end

    context 'when configured to false' do
      before do
        generated_cf_manifest['properties']['uaa']['cors']['enforce_system_zone_policy_in_all_zones'] = false
      end

      it 'is false in uaa.yml' do
        expect(parsed_yaml['cors']['enforceSystemZonePolicyInAllZones']).to eq(false)
      end
    end
  end

  describe 'logging formats' do
      let(:input) {'spec/input/test-defaults.yml'}

      let(:erb_template) {'../jobs/uaa/templates/config/log4j2.properties.erb'}
      let(:log4j2_template_path) {'spec/compare/default-log4j2-template.properties'}
      let(:as_yml) {false}

      let(:generated_cf_manifest) {generate_cf_manifest(input)}
      let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, as_yml)}

      context 'when uaa.logging.format.timestamp is not set' do
          it 'uses default value of rfc3339 and sets log_pattern to conform to rfc3339 with microsecond and UTC timezone' do
              log4j2_template = File.read(log4j2_template_path)
              expected_output_log4j2 = log4j2_template.sub! 'EXPECTED_LOG_PATTERN_PLACEHOLDER', "%d{yyyy-MM-dd'T'HH:mm:ss.nnnnnn}{GMT+0}Z"
              expect(parsed_yaml.to_s).to eq(expected_output_log4j2)
          end
      end

      context 'when uaa.logging.format.timestamp is configured to' do
          context 'rfc3339' do
            before do
              generated_cf_manifest['properties']['uaa']['logging'] = {'format' => {'timestamp' => 'rfc3339'}}
            end

            it 'sets log_pattern to conform to rfc3339 with microsecond and UTC timezone' do
                log4j2_template = File.read(log4j2_template_path)
                expected_output_log4j2 = log4j2_template.sub! 'EXPECTED_LOG_PATTERN_PLACEHOLDER', "%d{yyyy-MM-dd'T'HH:mm:ss.nnnnnn}{GMT+0}Z"
                expect(parsed_yaml.to_s).to eq(expected_output_log4j2)
            end
          end

          context 'rfc3339-legacy' do
            before do
              generated_cf_manifest['properties']['uaa']['logging'] = {'format' => {'timestamp' => 'rfc3339-legacy'}}
            end

            it 'sets log_pattern to conform to original rfc3339 format (millisecond precision) for compatibility' do
              log4j2_template = File.read(log4j2_template_path)
              expected_output_log4j2 = log4j2_template.sub! 'EXPECTED_LOG_PATTERN_PLACEHOLDER', "%d{yyyy-MM-dd'T'HH:mm:ss.SSSXXX}"
              expect(parsed_yaml.to_s).to eq(expected_output_log4j2)
            end
          end

          context 'deprecated' do
            before do
              generated_cf_manifest['properties']['uaa']['logging'] = {'format' => {'timestamp' => 'deprecated'}}
            end

            it 'sets log_pattern to deprecated format with irregular timestamps' do
              log4j2_template = File.read(log4j2_template_path)
              expected_output_log4j2 = log4j2_template.sub! 'EXPECTED_LOG_PATTERN_PLACEHOLDER', "%d{yyyy-MM-dd HH:mm:ss.SSS}"
              expect(parsed_yaml.to_s).to eq(expected_output_log4j2)
            end
          end

          context 'an invalid value' do
            before do
              generated_cf_manifest['properties']['uaa']['logging'] = {'format' => {'timestamp' => 'some-invalid-value'}}
            end

            it 'raises an error' do
              expect {parsed_yaml}.to raise_error(ArgumentError, /Invalid value for uaa.logging.format.timestamp./)
            end
          end
      end

      describe 'uaa.csp.script-src' do
        let(:input) {'spec/input/test-defaults.yml'}
        let(:erb_template) {'../jobs/uaa/templates/config/uaa.yml.erb'}
        let(:generated_cf_manifest) {generate_cf_manifest(input)}
        let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_cf_manifest, true)}

        context 'by default' do
          it 'is self in uaa.yml' do
            expect(parsed_yaml['csp']['script-src']).to eq ["'self'"]
          end
        end

        context 'when configured to empty' do
          before do
            generated_cf_manifest['properties']['uaa']['csp']['script-src'] = ['']
          end

          it 'raises an error' do
            expect {parsed_yaml}.to raise_error(ArgumentError, /Empty value for uaa.csp.script-src./)
          end
        end
      end

  end

  def self.perform_compare(input)
    generated_cf_manifest = generate_cf_manifest(input)
    parsed_uaa_yaml = read_and_parse_string_template '../jobs/uaa/templates/config/uaa.yml.erb', generated_cf_manifest, true
    tempDir = '/tmp/uaa-release-tests/' + input
    FileUtils.mkdir_p tempDir
    open(tempDir + '/uaa.yml', 'w') {|f|
      f.puts parsed_uaa_yaml.to_yaml(:Indent => 2, :UseHeader => true, :UseVersion => true)
    }
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
        read_and_parse_string_template '../jobs/uaa/templates/config/login.yml.erb', generated_cf_manifest, true
        raise 'This line should not be reached'
      rescue ArgumentError
        # expected
      end
      add_param_to_hash addProperty, 'value', generated_cf_manifest
    end
    read_and_parse_string_template '../jobs/uaa/templates/config/login.yml.erb', generated_cf_manifest, true

    begin
      read_and_parse_string_template '../jobs/uaa/templates/config/uaa.yml.erb', generated_cf_manifest, true
      raise 'This line should not be reached'
    rescue ArgumentError
      # expected
    end
    add_param_to_hash 'properties.uaa.jwt.signing_key', 'value', generated_cf_manifest
    read_and_parse_string_template '../jobs/uaa/templates/config/uaa.yml.erb', generated_cf_manifest, true
    generated_cf_manifest['properties']['uaa']['jwt']['signing_key'] = nil
    begin
      read_and_parse_string_template '../jobs/uaa/templates/config/uaa.yml.erb', generated_cf_manifest, true
      raise 'This line should not be reached'
    rescue ArgumentError
      # expected
    end
    add_param_to_hash 'properties.uaa.jwt.policy.active_key_id', 'value', generated_cf_manifest
    read_and_parse_string_template '../jobs/uaa/templates/config/uaa.yml.erb', generated_cf_manifest, true
    generated_cf_manifest['properties']['uaa']['jwt']['policy']['active_key_id'] = nil
    begin
      read_and_parse_string_template '../jobs/uaa/templates/config/uaa.yml.erb', generated_cf_manifest, true
      raise 'This line should not be reached'
    rescue ArgumentError
      # expected
    end

  end
end
