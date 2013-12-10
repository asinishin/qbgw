class SalesReceiptLineBeef
  include Beefcake::Message

  # Required
  required :operation,   :string, 1    
  required :sat_id,      :int32,  2
  required :txn_date,    :string, 3
  required :sat_line_id, :int32,  4
  required :sat_item_id, :int32,  5
  required :quantity,    :string, 6
  required :amount,      :string, 7 
  required :class_ref,   :string, 8
end

class SalesReceiptBeef
  include Beefcake::Message

  # Required
  required :operation,   :string, 1    
  required :sat_id,      :int32,  2

  required :customer_id, :int32,  3
  required :ref_number,  :string, 4
  required :txn_date,    :string, 5
  required :is_cashed,   :bool,   6

  # Optional
  # Deposit to account
  optional :account_ref, :string, 7

end
