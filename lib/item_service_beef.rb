class ItemServiceBeef
  include Beefcake::Message

  # Required
  required :operation,   :string, 1    
  required :sat_id,      :int32,  2    
  required :name,        :string, 3
  required :description, :string, 4
  required :account_ref, :string, 5

end
