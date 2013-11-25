class SalesReceiptBit < ActiveRecord::Base
  attr_accessible :customer_id, :operation, :ref_number, :sales_receipt_ref_id, :status, :txn_date

  belongs_to :sales_receipt_ref
end
