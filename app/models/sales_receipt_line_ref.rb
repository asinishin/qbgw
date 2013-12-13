class SalesReceiptLineRef < ActiveRecord::Base
  attr_accessible :sat_line_id, :sales_receipt_ref_id, :txn_line_id

  belongs_to :sales_receipt_ref
end
