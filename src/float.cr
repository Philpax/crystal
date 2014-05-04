lib C
  fun ceilf(x : Float32) : Float32
  fun ceil(x : Float64) : Float64
end

struct Float
  def +
    self
  end

  def floor
    to_i32
  end

  def round
    (self + 0.5).to_i32
  end
end

struct Float32
  MIN = -INFINITY
  MAX =  INFINITY

  def -
    0.0_f32 - self
  end

  def ceil
    C.ceilf(self).to_i
  end

  def **(other : Float32)
    Intrinsics.pow_f32(self, other)
  end

  def **(other)
    self ** other.to_f32
  end

  def to_s
    to_f64.to_s
  end
end

struct Float64
  MIN = -INFINITY
  MAX =  INFINITY

  def -
    0.0 - self
  end

  def ceil
    C.ceil(self).to_i
  end

  def **(other : Float64)
    Intrinsics.pow_f64(self, other)
  end

  def **(other)
    self ** other.to_f64
  end

  def to_s
    String.new_with_capacity(12) do |buffer|
      C.sprintf(buffer, "%g", self)
    end
  end
end
