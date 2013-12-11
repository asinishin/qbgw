class Delta

  def initialize(in_ids, out_ids, in_to_out, out_to_in)
    @in_ids = in_ids
    @out_ids = out_ids
    @in_to_out = in_to_out
    @out_to_in = out_to_in
  end

  def addition
    (@in_ids - @out_to_in.call(@out_ids)).each do |e|
      yield e
    end
  end

  def update
    b = @out_to_in.call(@out_ids) & @in_ids
    a = @in_to_out.call(b)
    (0..a.size - 1).map{ |i| [b[i], a[i]] }.each do |pair|
      yield pair[0], pair[1]
    end
  end

  def deletion
    @in_to_out.call(@out_to_in.call(@out_ids) - @in_ids).each do |e|
      yield e
    end
  end

end
