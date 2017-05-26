require 'json'
require 'yaml'
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

  def simplify_star(struct, k, v)
    return nil unless v.kind_of?(MockProperty)

    pattern = /([\w\-_\.]+).(\([\w\-_]+\))/
    if (left = k.match(pattern)) && (right = v.name.match(pattern)) then
      if left.length == 3 && right.length == 3 && left[2] == right[2]
        return nil unless struct.keys.count { |x| x.start_with?(left[1]+'.') } == 1

        return {:key => left[1], :value => MockProperty.new(right[1])}
      end
    end
    nil
  end

  def simplify_array(k, v)
    return nil unless (v.kind_of? Array) && (v.length == 1) && (v[0].kind_of? MockProperty) && (v[0].name.end_with? '[]')
    {:key => k, :value => MockProperty.new(v[0].name[0..-3])}
  end

  def simplify(struct)
    simplified = {}
    struct.each do |k, v|
      simplifiedKey = k
      simplifiedValue = v
      while simplification = (simplify_star(struct, simplifiedKey, simplifiedValue) || simplify_array(simplifiedKey, simplifiedValue))
        simplifiedKey, simplifiedValue = simplification.values_at(:key, :value)
      end
      simplified[simplifiedKey] = simplifiedValue
    end
    simplified
  end

  def render(params)
    result = simplify(render_str(params))

    spec = YAML.load(File.open('jobs/uaa/spec'))['properties']

    structured = {}
    result.keys.sort.each do |k|
      prop_descriptions = {}

      values = result[k].is_a?(Array) ? result[k] : [result[k]]
      values.each do |v|
        if v.is_a? String
          source_matches = v.scan /<(.+?)>/
          pp = source_matches.map { |match| match[0] }
        elsif v.is_a? MockProperty
          pp = [v.name]
        end

        pp.each do |p|
          pk = spec.keys.max do |a, b|
            aMatch = p.match("^#{Regexp.quote(a)}(?:$|\\.|\\[)")
            bMatch = p.match("^#{Regexp.quote(b)}(?:$|\\.|\\[)")

            aStrength = aMatch ? aMatch[0].length : 0
            bStrength = bMatch ? bMatch[0].length : 0

            aStrength <=> bStrength
          end

          if p.match("^#{Regexp.quote(pk)}(?:$|\\.|\\[)")
            pspec = spec[pk]
            prop_descriptions[pk] = pspec['description'] if pspec && pspec['description']
          end
        end
      end

      entry = {'*value' => result[k]}
      entry['*sources'] = prop_descriptions unless prop_descriptions.empty?
      add_value(structured, entry, *k.split('.'))
    end

    JSON.dump structured
  end

  def is_missing(hash, *keys)
    false
  end
end
