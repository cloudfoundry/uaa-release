require 'rspec'
require 'yaml'
require 'bosh/template/evaluation_context'
require 'json'
require 'deep_merge'
require 'support/yaml_eq'

describe 'uaa-release compare new and old ERB' do

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

    external_properties = YAML.load_file('spec/input/all-properties-set.yml')
    manifest_hash = manifest_hash.deep_merge!(external_properties)
    manifest_hash

  end

  let(:uaa_erb_yaml) { File.read(File.join(File.dirname(__FILE__), '../jobs/uaa/templates/uaa.yml.erb')) }
  let(:uaa_deprecated_erb_yaml) { File.read(File.join(File.dirname(__FILE__), '../jobs/uaa/templates/deprecated_uaa.yml.erb')) }
  let(:login_erb_yaml) { File.read(File.join(File.dirname(__FILE__), '../jobs/uaa/templates/login.yml.erb')) }
  let(:login_deprecated_erb_yaml) { File.read(File.join(File.dirname(__FILE__), '../jobs/uaa/templates/deprecated_login.yml.erb')) }

  subject(:parsed_uaa_yaml) do
    binding = Bosh::Template::EvaluationContext.new(deployment_manifest_fragment).get_binding
    YAML.load(ERB.new(uaa_erb_yaml).result(binding))
  end

  subject(:parsed_login_yaml) do
    binding = Bosh::Template::EvaluationContext.new(deployment_manifest_fragment).get_binding
    YAML.load(ERB.new(login_erb_yaml).result(binding))
  end

  subject(:parsed_deprecated_uaa_yaml) do
    binding = Bosh::Template::EvaluationContext.new(deployment_manifest_fragment).get_binding
    YAML.load(ERB.new(uaa_deprecated_erb_yaml).result(binding))
  end

  subject(:parsed_deprecated_login_yaml) do
    binding = Bosh::Template::EvaluationContext.new(deployment_manifest_fragment).get_binding
    YAML.load(ERB.new(login_deprecated_erb_yaml).result(binding))
  end

  context 'given app-properties-set inputs' do
    it "uaa.yml should match" do
      expected = parsed_deprecated_uaa_yaml.to_yaml
      actual = parsed_uaa_yaml.to_yaml
      expect(actual).to yaml_eq(expected)
    end

    it "login.yml should match" do
      expected = parsed_deprecated_login_yaml.to_yaml
      actual = parsed_login_yaml.to_yaml
      expect(actual).to yaml_eq(expected)
    end
  end
end
