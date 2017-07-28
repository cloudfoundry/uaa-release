require 'rspec'
require 'nokogiri'
require 'bosh/template/evaluation_context'
require 'spec_helper'

describe 'tomcat.server.xml' do
  def compile_erb(erb_template_location, manifest)
    erb_content = File.read(File.join(File.dirname(__FILE__), erb_template_location))
    binding = Bosh::Template::EvaluationContext.new(manifest).get_binding
    ERB.new(erb_content).result(binding)
  end

  context 'using bosh links' do
    let(:compiled_xml) { compile_erb(template, manifest) }
    let(:template) { '../jobs/uaa/templates/tomcat.server.xml.erb' }
    let(:internal_proxies) do
      config = Nokogiri::XML.parse(compiled_xml)
      config.xpath('//Valve')[0].attributes['internalProxies'].value
    end

    context 'when uaa.proxy.servers is configured in the manifest' do
      before(:each) do
        manifest['properties']['uaa']['proxy']['servers'] = ['127.1.0.1', '127.1.0.2', '127.1.0.3']
        manifest['properties']['uaa']['proxy_ips_regex'] = 'proxy_ips_regex'
        manifest['links'] = {
            'router' => {'instances' => [{'address' => 'link.ed-add.ress'}]}
        }

      end
      let(:manifest) { generate_cf_manifest('spec/input/all-properties-set.yml') }

      it 'manifest values take precedence over bosh-linked configuration' do
        expect(internal_proxies).to eq 'link\.ed-add\.ress|127\.1\.0\.1|127\.1\.0\.2|127\.1\.0\.3|proxy_ips_regex'
      end
    end
    
    context 'when uaa.proxy_ips_regex is in the manifest' do
      let(:manifest) { generate_cf_manifest('spec/input/all-properties-set.yml') }

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

      let(:manifest) { generate_cf_manifest('spec/input/all-properties-set.yml', links) }

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
