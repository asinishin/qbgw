class QbSalesReceiptLine < ActiveRecord::Base
  attr_accessible :amount, :class_ref, :item_ref, :qb_sales_receipt_id, :quantity, :txn_line_id

  belongs_to :qb_sales_receipt
end
