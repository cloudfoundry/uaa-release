require 'rspec'
require 'yaml'
require 'bosh/template/evaluation_context'
require 'json'
require 'deep_merge'
require 'support/yaml_eq'

describe 'uaa-release erb generation' do

  def self.add_param_to_hash param_name, param_value, target_hash = {}
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

  def self.generate_cf_manifest file_name
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
    external_properties = YAML.load_file(file_name)
    manifest_hash = manifest_hash.deep_merge!(external_properties)
    manifest_hash
  end

  def self.perform_erb_transformation_as_yaml erb_file, manifest_file
    YAML.load(perform_erb_transformation_as_string erb_file, manifest_file)
  end

  def self.perform_erb_transformation_as_string erb_file, manifest_file
    binding = Bosh::Template::EvaluationContext.new(manifest_file).get_binding
    ERB.new(erb_file).result(binding)
  end


  def self.perform_compare input, output_uaa, output_login, output_log4j
    uaa_erb_yaml = File.read(File.join(File.dirname(__FILE__), '../jobs/uaa/templates/uaa.yml.erb'))
    login_erb_yaml =  File.read(File.join(File.dirname(__FILE__), '../jobs/uaa/templates/login.yml.erb'))
    log4j_erb_properties =  File.read(File.join(File.dirname(__FILE__), '../jobs/uaa/templates/log4j.properties.erb'))

    generated_cf_manifest = generate_cf_manifest(input)
    parsed_uaa_yaml = perform_erb_transformation_as_yaml(uaa_erb_yaml, generated_cf_manifest)
    parsed_login_yaml = perform_erb_transformation_as_yaml(login_erb_yaml, generated_cf_manifest)
    parsed_log4j_properties = perform_erb_transformation_as_string(log4j_erb_properties, generated_cf_manifest)

    it "uaa.yml should match" do
      expected = File.read(output_uaa)
      actual = parsed_uaa_yaml.to_yaml
      expect(actual).to yaml_eq(expected)
    end
    it "login.yml should match" do
      expected = File.read(output_login)
      actual = parsed_login_yaml.to_yaml
      expect(actual).to yaml_eq(expected)
    end
    it "log4j.properties should match" do
      expected = File.read(output_log4j)
      actual = parsed_log4j_properties.to_s
      expect(actual).to eq(expected)
    end

  end

  perform_compare 'spec/input/bosh-lite.yml', 'spec/compare/bosh-lite-uaa.yml', 'spec/compare/bosh-lite-login.yml', 'spec/compare/default-log4j.properties'
  perform_compare 'spec/input/all-properties-set.yml', 'spec/compare/all-properties-set-uaa.yml', 'spec/compare/all-properties-set-login.yml', 'spec/compare/all-properties-set-log4j.properties'
  perform_compare 'spec/input/test-defaults.yml', 'spec/compare/test-defaults-uaa.yml', 'spec/compare/test-defaults-login.yml', 'spec/compare/default-log4j.properties'

end
