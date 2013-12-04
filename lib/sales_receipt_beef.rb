class SalesReceiptLineBeef
  include Beefcake::Message

  # Required
  required :operation,   :string, 1    
  required :sat_id,      :int32,  2
  required :sat_line_id, :int32,  3
  required :sat_item_id, :int32,  4
  required :quantity,    :string, 5
  required :amount,      :string, 6 
  required :class_ref,   :string, 7
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
