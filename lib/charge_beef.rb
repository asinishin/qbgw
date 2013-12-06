class ChargeBeef
  include Beefcake::Message

  # Required
  required :operation,   :string, 1    

  required :sat_id,      :int32,  2
  required :customer_id, :int32,  3
  required :ref_number,  :string, 4
  required :txn_date,    :string, 5

  required :sat_line_id, :int32,  6
  required :sat_item_id, :int32,  7
  required :quantity,    :string, 8
  required :amount,      :string, 9 
  required :class_ref,   :string, 10
end
