require 'rspec'
require 'yaml'
require 'bosh/template/evaluation_context'
require 'json'
require 'support/yaml_eq'
require 'spec_helper'

describe 'boot.application.yml' do
  def perform_erb_transformation_as_string(erb_file, manifest_file)
      binding = Bosh::Template::EvaluationContext.new(manifest_file, nil).get_binding
      ERB.new(erb_file).result(binding)
  end

  def perform_erb_transformation_as_yaml(erb_file, manifest_file)
    YAML.load(
        perform_erb_transformation_as_string(erb_file, manifest_file)
    )
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

  context 'application.yml' do
    let(:manifest) {'spec/input/all-properties-set.yml'}
    let(:output_application_yaml) {'spec/compare/all-properties-boot-application.yml'}
    let(:erb_template) {'../jobs/uaa/templates/config/boot/application.yml.erb'}
    let(:as_yml) {true}
    let(:generated_uaa_manifest) {generate_cf_manifest(manifest)}
    let(:parsed_yaml) {read_and_parse_string_template(erb_template, generated_uaa_manifest, as_yml)}



    context 'when using default values' do
      it 'yaml matches the expected result' do
        yml_compare(output_application_yaml, parsed_yaml.to_yaml)
      end
    end

    context 'when uaa.localhost_http_port is valid' do
      before(:each) do
        generated_uaa_manifest['properties']['uaa']['localhost_http_port'] = 2000
      end

      it 'has an http connector with value of uaa.localhost_http_port' do
        expect(parsed_yaml['server']['http']['port']).to eq 2000
      end
    end

    context 'when uaa.localhost_http_port is invalid (-1)' do
      before(:each) do
        generated_uaa_manifest['properties']['uaa']['localhost_http_port'] = -1
      end

      it 'returns an error' do
        expect {parsed_yaml}.to raise_error(ArgumentError, 'Invalid value (-1) specified for uaa.localhost_http_port, please specify a valid port number in this range [1024-65535]')
      end
    end

    context 'when uaa.localhost_http_port is invalid (1023)' do
      before(:each) do
        generated_uaa_manifest['properties']['uaa']['localhost_http_port'] = 1023
      end

      it 'returns an error' do
        expect {parsed_yaml}.to raise_error(ArgumentError, 'Invalid value (1023) specified for uaa.localhost_http_port, please specify a valid port number in this range [1024-65535]')
      end
    end

    context 'when uaa.localhost_http_port is invalid (65536)' do
      before(:each) do
        generated_uaa_manifest['properties']['uaa']['localhost_http_port'] = 65536
      end

      it 'returns an error' do
        expect {parsed_yaml}.to raise_error(ArgumentError, 'Invalid value (65536) specified for uaa.localhost_http_port, please specify a valid port number in this range [1024-65535]')
      end
    end

    context 'when uaa.ssl.port is valid' do
      before(:each) do
        generated_uaa_manifest['properties']['uaa']['ssl']['port'] = 3333
      end

      it 'has an http connector with value of uaa.localhost_http_port' do
        expect(parsed_yaml['server']['port']).to eq 3333
      end
    end

    context 'when uaa.ssl.port is invalid (-1)' do
      before(:each) do
        generated_uaa_manifest['properties']['uaa']['ssl']['port'] = -1
      end

      it 'returns an error' do
        expect {parsed_yaml}.to raise_error(ArgumentError, 'Invalid value (-1) specified for uaa.ssl.port, please specify a valid port number in this range [1024-65535]')
      end
    end

    context 'when uaa.ssl.port is invalid (1023)' do
      before(:each) do
        generated_uaa_manifest['properties']['uaa']['ssl']['port'] = 1023
      end

      it 'returns an error' do
        expect {parsed_yaml}.to raise_error(ArgumentError, 'Invalid value (1023) specified for uaa.ssl.port, please specify a valid port number in this range [1024-65535]')
      end
    end

    context 'when uaa.ssl.port is invalid (65536)' do
      before(:each) do
        generated_uaa_manifest['properties']['uaa']['ssl']['port'] = 65536
      end

      it 'returns an error' do
        expect {parsed_yaml}.to raise_error(ArgumentError, 'Invalid value (65536) specified for uaa.ssl.port, please specify a valid port number in this range [1024-65535]')
      end
    end

    context 'when uaa.localhost_http_port is the same as uaa.ssl.port' do
      before(:each) do
        generated_uaa_manifest['properties']['uaa']['ssl']['port'] = 9090
        generated_uaa_manifest['properties']['uaa']['localhost_http_port'] = 9090
      end

      it 'returns an error' do
        expect {parsed_yaml}.to raise_error(ArgumentError, 'Please specify different values for uaa.ssl.port and uaa.localhost_http_port')
      end
    end

    context 'when uaa.keepalive_timeout is invalid (-1)' do
      before(:each) do
        generated_uaa_manifest['properties']['uaa']['keepalive_timeout'] = -2
      end

      it 'returns an error' do
        expect {parsed_yaml}.to raise_error(ArgumentError, 'Invalid value (-2) specified for uaa.keepalive_timeout, please specify either a positive integer value or -1')
      end
    end

    context 'using bosh links' do
      let(:internal_proxies) do
        parsed_yaml['server']['tomcat']['remoteip']['internal-proxies']
      end

      context 'when uaa.proxy_ips_regex is in the manifest' do
        it 'includes the proxy_ips_regex when uaa.proxy.servers not set and bosh links not available' do
          generated_uaa_manifest['properties']['uaa']['proxy']['servers'] = []
          generated_uaa_manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
          generated_uaa_manifest['links'] = {}

          expect(internal_proxies).to include('proxy_ips_regex')
        end

        it 'includes proxy_ips_regex when uaa.proxy.servers are set and bosh links are not available' do
          generated_uaa_manifest['properties']['uaa']['proxy']['servers'] = ['1.1.1.1']
          generated_uaa_manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
          generated_uaa_manifest['links'] = {}

          expect(internal_proxies).to include('proxy_ips_regex')
        end

        it 'includes proxy_ips_regex when uaa.proxy.servers not set and bosh link is available' do
          generated_uaa_manifest['properties']['uaa']['proxy']['servers'] = []
          generated_uaa_manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
          generated_uaa_manifest['links'] = {
              'router' => {'instances' => [{'address' => 'linked-address'}]}
          }

          expect(internal_proxies).to include('proxy_ips_regex')
        end

        it 'includes proxy_ips_regex when uaa.proxy.servers is set and bosh link is available' do
          generated_uaa_manifest['properties']['uaa']['proxy']['servers'] = ['1.12.3.4']
          generated_uaa_manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
          generated_uaa_manifest['links'] = {
              'router' => {'instances' => [{'address' => 'linked-address'}]}
          }

          expect(internal_proxies).to include('proxy_ips_regex')
        end
      end
      context 'when uaa.proxy.servers is left to default value in the manifest' do
        before(:each) do
          generated_uaa_manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
          generated_uaa_manifest['properties']['uaa']['proxy']['servers'] = []
        end

        let(:generated_uaa_manifest) {generate_cf_manifest('spec/input/all-properties-set.yml', links)}

        context 'when a bosh-link is available' do
          let(:links) {{
            'router' => {'instances' => [{'address' => 'linked-address'}]}
          }}

          it 'uses the bosh-linked router config' do
            expect(internal_proxies).to eq('linked-address|proxy_ips_regex')
          end
        end

        context 'when there is no bosh-link available' do
          before(:each) do
            generated_uaa_manifest['properties']['uaa']['proxy_ips_regex'] = ''
            generated_uaa_manifest['properties']['uaa']['proxy']['servers'] = []
          end
          let(:links) {{}}

          it 'uses the default internal proxies list' do
            expect(internal_proxies).to eq '10.d{1,3}.d{1,3}.d{1,3}|192.168.d{1,3}.d{1,3}|169.254.d{1,3}.d{1,3}|127.d{1,3}.d{1,3}.d{1,3}|172.1[6-9]{1}.d{1,3}.d{1,3}|172.2[0-9]{1}.d{1,3}.d{1,3}|172.3[0-1]{1}.d{1,3}.d{1,3}'
          end
        end
      end
    end
  end
end