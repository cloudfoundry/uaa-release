require 'rspec'
require 'yaml'
require 'bosh/template/evaluation_context'
require 'json'
require 'deep_merge'
require 'support/yaml_eq'

describe 'uaa-release yaml generation' do

  def add_param_to_hash param_name, param_value, target_hash = {}
    begin
      a = target_hash
      p = param_name.split(/[\/\.]/)
      val = param_value
      # the following, somewhat complex line, runs through the existing (?) tree, making sure to preserve existing values and add values where needed.
      p.each_index { |i| p[i].strip! ; n = p[i].match(/^[0-9]+$/) ? p[i].to_i : p[i].to_s ; p[i+1] ? [ ( a[n] ||= ( p[i+1].empty? ? [] : {} ) ), ( a = a[n]) ] : ( a.is_a?(Hash) ? (a[n] ? (a[n].is_a?(Array) ? (a << val) : a[n] = [a[n], val] ) : (a[n] = val) ) : (a << val) ) }
    rescue Exception => e
      warn '(Silent): parameters parse error for #{param_name} ... maybe conflicts with a different set?'
      target_hash[param_name] = param_value
    end
  end


  let(:deployment_manifest_fragment) do

    spec_defaults = YAML
                      .load_file('jobs/uaa/spec')['properties']
                      .keep_if { |k,v| v.has_key?('default') }
                      .map { |k, v| [k, v['default']] }
                      .to_h

    new_hash = {}
    spec_defaults.each do |key, value|
      if key.include? '.'
        add_param_to_hash(key, value, new_hash)
      else
        new_hash[key] = value
      end
    end

    #add our properties here
    # new_hash['login']['protocol'] = 'https'
    # new_hash['uaa']['url'] = 'https://uaa.test.com'

    manifest_hash = {
        'properties' => new_hash
    }

    external_properties = YAML.load_file('spec/input/bosh-lite.yml')

    manifest_hash = manifest_hash.deep_merge!(external_properties)

    manifest_hash

  end

  let(:uaa_erb_yaml) { File.read(File.join(File.dirname(__FILE__), '../jobs/uaa/templates/uaa.yml.erb')) }
  let(:login_erb_yaml) { File.read(File.join(File.dirname(__FILE__), '../jobs/uaa/templates/login.yml.erb')) }

  subject(:parsed_uaa_yaml) do
    binding = Bosh::Template::EvaluationContext.new(deployment_manifest_fragment).get_binding
    YAML.load(ERB.new(uaa_erb_yaml).result(binding))
  end

  subject(:parsed_login_yaml) do
    binding = Bosh::Template::EvaluationContext.new(deployment_manifest_fragment).get_binding
    YAML.load(ERB.new(login_erb_yaml).result(binding))
  end

  context 'given bosh-lite inputs' do
    it "uaa.yml should match" do
      #parsed_uaa_yaml is a hash with the result
      #puts "Generated Yaml File:\n" + parsed_uaa_yaml.to_yaml( :Indent => 2)

      expected = File.read('spec/compare/bosh-lite-uaa.yml')
      actual = parsed_uaa_yaml.to_yaml

      expect(actual).to yaml_eq(expected)
      # expect(parsed_uaa_yaml['oauth']['clients']['admin']['secret']).to eq('admin-secret')
    end

    it "login.yml should match" do
      expected = File.read('spec/compare/bosh-lite-login.yml')
      actual = parsed_login_yaml.to_yaml
      puts "actual:\n" + parsed_login_yaml.to_yaml(:indentation => 2)
      expect(actual).to yaml_eq(expected)
    end


    # context "When NATS's HTTP interface is specified" do
    #   before do
    #     deployment_manifest_fragment['properties']['nats']['http'] = {
    #       'port' => 8081,
    #       'user' => 'http-user',
    #       'password' => 'http-password',
    #     }
    #   end
    #
    #   it 'should template the appropriate parameters' do
    #     expect(parsed_uaa_yaml['http']['port']).to eq(8081)
    #     expect(parsed_uaa_yaml['http']['user']).to eq('http-user')
    #     expect(parsed_uaa_yaml['http']['password']).to eq('http-password')
    #   end
    # end
  end
end
