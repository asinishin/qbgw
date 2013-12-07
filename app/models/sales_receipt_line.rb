class SalesReceiptLine < ActiveRecord::Base
  attr_accessible :amount, :class_ref, :item_id, :quantity,
                  :sales_receipt_bit_id, :txn_line_id

  belongs_to :sales_receipt_bit
end
