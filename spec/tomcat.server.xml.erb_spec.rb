require 'rspec'
require 'nokogiri'
require 'bosh/template/evaluation_context'
require 'spec_helper'
require 'yaml'

describe 'tomcat.server.xml' do
  def read_file(relative_path)
    File.read(File.join(File.dirname(__FILE__), relative_path))
  end

  def compile_erb(erb_template_location, manifest)
    erb_content = read_file(erb_template_location)
    binding = Bosh::Template::EvaluationContext.new(manifest, nil).get_binding
    ERB.new(erb_content).result(binding)
  end

  let(:compiled_xml) {compile_erb(template, manifest)}
  let(:template) {'../jobs/uaa/templates/config/tomcat/tomcat.server.xml.erb'}
  let(:manifest) {generate_cf_manifest('spec/input/all-properties-set.yml')}

  it 'matches the expected result' do
    expect(compiled_xml.gsub(/\s/, '')).to eq(read_file('compare/all-properties-tomcat-server.xml').gsub(/\s/, ''))
  end

  let(:connectors) do
    config = Nokogiri::XML.parse(compiled_xml)
    config.xpath('//Connector')
  end

  let(:http_connector) do
    connectors[0]
  end

  let(:https_connector) do
    connectors[1]
  end

  it 'has two connector elements' do
    expect(connectors.length).to eq(2)
  end

  context 'when uaa.localhost_http_port is valid' do
    before(:each) do
      manifest['properties']['uaa']['localhost_http_port'] = 2000
    end

    it 'has an http connector with value of uaa.localhost_http_port' do
      expect(http_connector["port"]).to eq("2000")
    end
  end

  context 'when uaa.localhost_http_port is invalid (-1)' do
    before(:each) do
      manifest['properties']['uaa']['localhost_http_port'] = -1
    end

    it 'returns an error' do
      expect {compiled_xml}.to raise_error(ArgumentError, 'Invalid value (-1) specified for uaa.localhost_http_port, please specify a valid port number in this range [1024-65535]')
    end
  end

  context 'when uaa.localhost_http_port is invalid (1023)' do
    before(:each) do
      manifest['properties']['uaa']['localhost_http_port'] = 1023
    end

    it 'returns an error' do
      expect {compiled_xml}.to raise_error(ArgumentError, 'Invalid value (1023) specified for uaa.localhost_http_port, please specify a valid port number in this range [1024-65535]')
    end
  end

  context 'when uaa.localhost_http_port is invalid (65536)' do
    before(:each) do
      manifest['properties']['uaa']['localhost_http_port'] = 65536
    end

    it 'returns an error' do
      expect {compiled_xml}.to raise_error(ArgumentError, 'Invalid value (65536) specified for uaa.localhost_http_port, please specify a valid port number in this range [1024-65535]')
    end
  end

  context 'when uaa.ssl.port is valid' do
    before(:each) do
      manifest['properties']['uaa']['ssl']['port'] = 3333
    end

    it 'has an http connector with value of uaa.localhost_http_port' do
      expect(https_connector["port"]).to eq("3333")
    end
  end

  context 'when uaa.ssl.port is invalid (-1)' do
    before(:each) do
      manifest['properties']['uaa']['ssl']['port'] = -1
    end

    it 'returns an error' do
      expect {compiled_xml}.to raise_error(ArgumentError, 'Invalid value (-1) specified for uaa.ssl.port, please specify a valid port number in this range [1024-65535]')
    end
  end

  context 'when uaa.ssl.port is invalid (1023)' do
    before(:each) do
      manifest['properties']['uaa']['ssl']['port'] = 1023
    end

    it 'returns an error' do
      expect {compiled_xml}.to raise_error(ArgumentError, 'Invalid value (1023) specified for uaa.ssl.port, please specify a valid port number in this range [1024-65535]')
    end
  end

  context 'when uaa.ssl.port is invalid (65536)' do
    before(:each) do
      manifest['properties']['uaa']['ssl']['port'] = 65536
    end

    it 'returns an error' do
      expect {compiled_xml}.to raise_error(ArgumentError, 'Invalid value (65536) specified for uaa.ssl.port, please specify a valid port number in this range [1024-65535]')
    end
  end

  context 'when uaa.localhost_http_port is the same as uaa.ssl.port' do
    before(:each) do
      manifest['properties']['uaa']['ssl']['port'] = 9090
      manifest['properties']['uaa']['localhost_http_port'] = 9090
    end

    it 'returns an error' do
      expect {compiled_xml}.to raise_error(ArgumentError, 'Please specify different values for uaa.ssl.port and uaa.localhost_http_port')
    end
  end

  context 'when uaa.keepalive_timeout is invalid (-1)' do
    before(:each) do
      manifest['properties']['uaa']['keepalive_timeout'] = -2
    end

    it 'returns an error' do
      expect {compiled_xml}.to raise_error(ArgumentError, 'Invalid value (-2) specified for uaa.keepalive_timeout, please specify either a positive integer value or -1')
    end
  end

  context 'using bosh links' do
    let(:internal_proxies) do
      config = Nokogiri::XML.parse(compiled_xml)
      config.xpath('//Valve')[0].attributes['internalProxies'].value
    end

    context 'when uaa.proxy_ips_regex is in the manifest' do
      it 'includes the proxy_ips_regex when uaa.proxy.servers not set and bosh links not available' do
        manifest['properties']['uaa']['proxy']['servers'] = []
        manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
        manifest['links'] = {}

        expect(internal_proxies).to include('proxy_ips_regex')
      end

      it 'includes proxy_ips_regex when uaa.proxy.servers are set and bosh links are not available' do
        manifest['properties']['uaa']['proxy']['servers'] = ['1.1.1.1']
        manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
        manifest['links'] = {}

        expect(internal_proxies).to include('proxy_ips_regex')
      end

      it 'includes proxy_ips_regex when uaa.proxy.servers not set and bosh link is available' do
        manifest['properties']['uaa']['proxy']['servers'] = []
        manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
        manifest['links'] = {
            'router' => {'instances' => [{'address' => 'linked-address'}]}
        }

        expect(internal_proxies).to include('proxy_ips_regex')
      end

      it 'includes proxy_ips_regex when uaa.proxy.servers is set and bosh link is available' do
        manifest['properties']['uaa']['proxy']['servers'] = ['1.12.3.4']
        manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
        manifest['links'] = {
            'router' => {'instances' => [{'address' => 'linked-address'}]}
        }

        expect(internal_proxies).to include('proxy_ips_regex')
      end
    end

    context 'when uaa.proxy.servers is left to default value in the manifest' do
      before(:each) do
        manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
        manifest['properties']['uaa']['proxy']['servers'] = []
      end

      let(:manifest) {generate_cf_manifest('spec/input/all-properties-set.yml', links)}

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
          manifest['properties']['uaa']['proxy_ips_regex'] = ''
          manifest['properties']['uaa']['proxy']['servers'] = []
        end
        let(:links) {{}}

        it 'uses the default internal proxies list' do
          expect(internal_proxies).to eq '10.d{1,3}.d{1,3}.d{1,3}|192.168.d{1,3}.d{1,3}|169.254.d{1,3}.d{1,3}|127.d{1,3}.d{1,3}.d{1,3}|172.1[6-9]{1}.d{1,3}.d{1,3}|172.2[0-9]{1}.d{1,3}.d{1,3}|172.3[0-1]{1}.d{1,3}.d{1,3}'
        end
      end
    end
  end
end
