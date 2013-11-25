class SalesReceiptLineBeef
  include Beefcake::Message

  required :item_id,     :int32,  1
  required :quantity,    :string, 2
  required :amount,      :string, 3 
  required :class_ref,   :string, 4
end

class SalesReceiptBeef
  include Beefcake::Message

  # Required
  required :operation,   :string, 1    
  required :sat_id,      :int32,  2

  required :customer_id, :int32,  3
  required :ref_number,  :string, 4
  required :txn_date,    :string, 5

  repeated :lines, SalesReceiptLineBeef, 6, :packed => true

end
