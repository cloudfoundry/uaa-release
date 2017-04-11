require 'json'
require_relative 'mock_property'

module DocOverrides
  def p(*args)
    MockProperty.new(args[0])
  end

  class ElseBlock
    def else()
    end
  end

  def if_p(*str)
    props = str.map { |p| MockProperty.new(p) }

    yield(*props)

    return ElseBlock.new
  end

  def error_if_exists(error)
  end

  def render_str(params, result={})
    params.each do |k, v|
      if v.kind_of?(Hash)
        flat = {}
        v.each do |kk, vv|
          flat["#{k}.#{kk}"] = vv
        end
        render_str(flat, result)
      else
        result[k] = v
      end
    end

    result
  end

  def simplifyStar(struct, k, v)
    return nil unless (v.kind_of? MockProperty) && k.end_with?('.*') && v.name.end_with?('.*') && struct.keys.count { |aKey| aKey.start_with?(k[0..-3]+'.') } < 2
    {:key => k[0..-3], :value => MockProperty.new(v.name[0..-3])}
  end

  def simplifyArray(k, v)
    return nil unless (v.kind_of? Array) && (v.length == 1) && (v[0].kind_of? MockProperty) && (v[0].name.end_with? '[]')
    {:key => k, :value => MockProperty.new(v[0].name[0..-3])}
  end

  def simplify(struct)
    simplified = {}
    struct.each do |k, v|
      simplifiedKey = k
      simplifiedValue = v
      while simplification = (simplifyStar(struct, simplifiedKey, simplifiedValue) || simplifyArray(simplifiedKey, simplifiedValue))
        simplifiedKey, simplifiedValue = simplification.values_at(:key, :value)
      end
      simplified[simplifiedKey] = simplifiedValue
    end
    simplified
  end

  def render(params)
    result = render_str(params)

    result = simplify(result)
    spec = YAML.load_file(File.join(File.dirname(__FILE__), '../spec'))

    structured = {}
    result.keys.sort.each do |k|
      spec_file_property_name = result[k].to_s.gsub(/[\<\>]/,'')
      properties = {
          'config_mapping' => result[k],
          'description' => nil,
          'default' => nil
      }

      if spec['properties'].has_key?(spec_file_property_name)
        properties['description'] = spec['properties'][spec_file_property_name]['description']
        properties['default'] = spec['properties'][spec_file_property_name]['default']
      end
      add_value(structured, properties, *k.split('.'))
    end

    JSON.dump structured
  end

  def is_missing(hash, *keys)
    false
  end
end
