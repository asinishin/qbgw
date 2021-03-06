class CustomerBeef
  include Beefcake::Message

  # Required
  required :operation,  :string, 1    
  required :sat_id,     :int32,  2    
  required :first_name, :string, 3
  required :last_name,  :string, 4

  # Optional
  # optional :tag, :string, 3

  # Repeated
  # repeated :ary,  :fixed64, 4
  # repeated :pary, :fixed64, 5, :packed => true

  # Enums - Simply use a Module (NOTE: defaults are optional)
  # module Foonum
  #  A = 1
  #  B = 2
  # end

  # As per the spec, defaults are only set at the end
  # of decoding a message, not on object creation.
  # optional :foo, Foonum, 6, :default => Foonum::B
end
