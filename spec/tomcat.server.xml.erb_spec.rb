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

    context 'when uaa.proxy.servers is configured' do
      let(:manifest) { generate_cf_manifest('spec/input/all-properties-set.yml', links) }
      let(:links) {{
          'router' => {'instances' => [{address: 'someaddress'}]}
      }}

      it 'takes precedence over bosh-linked configuration' do
        config = Nokogiri::XML.parse(compiled_xml)
        internal_proxies = config.xpath('//Valve')[0].attributes['internalProxies'].value
        expect(internal_proxies).not_to include('someaddress')
      end
    end

    context 'when uaa.proxy.servers is not congfiured' do
      before(:each) { manifest['properties']['uaa']['proxy'].delete 'servers' }
      let(:links) {{
          'router' => {'instances' => [{'address' => 'linked-address'}]}
      }}
      let(:manifest) { generate_cf_manifest('spec/input/all-properties-set.yml', links) }

      it 'tries to fall back to a bosh-linked router config' do
        config = Nokogiri::XML.parse(compiled_xml)
        internal_proxies = config.xpath('//Valve')[0].attributes['internalProxies'].value
        expect(internal_proxies).to include('linked-address')
      end
    end

    context 'when neither uaa.proxy.servers nor bosh-linked router is available' do
      before(:each) { manifest['properties']['uaa']['proxy'].delete('servers') }
      let(:links) {{}}
      let(:manifest) { generate_cf_manifest('spec/input/all-properties-set.yml', links) }

      it 'uses a default proxy_ips_regex' do
        config = Nokogiri::XML.parse(compiled_xml)
        internal_proxies = config.xpath('//Valve')[0].attributes['internalProxies'].value
        expect(internal_proxies).not_to be_nil
      end
    end
  end
end
