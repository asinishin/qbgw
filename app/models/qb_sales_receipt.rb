class QbSalesReceipt < ActiveRecord::Base
  attr_accessible :ref_number, :snapshot_id, :txn_date, :txn_id

  belongs_to :snapshot
  has_many   :sales_receipt_lines

end
