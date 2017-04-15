def generate_cf_manifest(file_name, links={})
  spec_defaults = YAML.load_file('jobs/uaa/spec')['properties'].keep_if { |k,v| v.has_key?('default') }.map { |k, v| [k, v['default']] }.to_h
  new_hash = {}
  spec_defaults.each do |key, value|
    if key.include? '.'
      add_param_to_hash(key, value, new_hash)
    else
      new_hash[key] = value
    end
  end

  manifest_hash = {
      'links' => links,
      'properties' => new_hash
  }

  external_properties = YAML.load_file(file_name)
  manifest_hash = manifest_hash.deep_merge!(external_properties)
  manifest_hash
end

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
