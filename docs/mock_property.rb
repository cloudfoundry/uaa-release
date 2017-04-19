class MockProperty
  attr_reader :name

  def initialize(name)
    @name = name.kind_of?(Array) ? name[0] : name
  end

  def [](key)
    MockProperty.new("#{name}.#{key}")
  end

  class FindElem
    def [](key)
      @key = key
      @capt = FindCapt.new
      @capt
    end

    attr_reader :key, :capt
  end

  class FindCapt
    def ==(value)
      @val = value
      true
    end

    attr_reader :val
  end

  def find()
    elem = FindElem.new
    yield(elem)
    MockProperty.new("#{name}[#{elem.key}=#{elem.capt.val}]")
  end

  def each(&blk)
    if(blk.arity == 1)
      yield(MockProperty.new("#{name}[]"))
    elsif (blk.arity == 2)
      star_name = Proc.new(&blk).parameters[0][1]
      yield("(#{star_name})", MockProperty.new("#{name}.(#{star_name})"))
    end
  end

  def sub(before, after)
    self
  end

  def reject()
    self
  end

  def +(arg)
    "#{self}#{arg}"
  end

  def to_str
    to_s
  end

  def to_s
    "<#{@name}>"
  end

  def join(delim)
    self
  end
end
