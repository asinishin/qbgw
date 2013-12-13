class SalesReceiptRef < ActiveRecord::Base
  attr_accessible :edit_sequence, :qb_id, :sat_id

  has_many :sales_receipt_line_refs, dependent: :destroy
end
