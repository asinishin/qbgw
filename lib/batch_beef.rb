class BatchBeef
  include Beefcake::Message

  # Required
  required :date_from,  :string, 1    
  required :date_to,    :string, 2    

end
