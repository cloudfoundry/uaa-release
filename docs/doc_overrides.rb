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

    structured = {}
    result.keys.sort.each do |k|
      add_value(structured, result[k], *k.split('.'))
    end

    JSON.dump structured
  end

  def is_missing(hash, *keys)
    false
  end
end
