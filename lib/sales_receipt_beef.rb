class SalesReceiptLineBeef
  include Beefcake::Message

  # Required
  required :operation,   :string, 1    
  required :sat_id,      :int32,  2

  required :sat_item_id, :int32,  3
  required :quantity,    :string, 4
  required :amount,      :string, 5 
  required :class_ref,   :string, 6
end

class SalesReceiptBeef
  include Beefcake::Message

  # Required
  required :operation,   :string, 1    
  required :sat_id,      :int32,  2

  required :customer_id, :int32,  3
  required :ref_number,  :string, 4
  required :txn_date,    :string, 5
end
