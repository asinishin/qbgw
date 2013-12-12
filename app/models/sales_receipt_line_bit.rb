class SalesReceiptLineBit < ActiveRecord::Base
  attr_accessible :amount, :class_ref, :item_id, :quantity, :operation,
                  :sales_receipt_bit_id, :sales_receipt_line_refs

  belongs_to :sales_receipt_bit
end