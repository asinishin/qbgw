class SalesReceiptLineBit < ActiveRecord::Base
  attr_accessible :amount, :class_ref, :item_id, :quantity, :operation,
                  :sales_receipt_bit_id, :sales_receipt_line_ref_id

  belongs_to :sales_receipt_bit
  belongs_to :sales_receipt_line_ref
end
