class AddIndexToSales < ActiveRecord::Migration
  def change
    add_index :sales_receipt_refs, :sat_id, :unique => true
    add_index :sales_receipt_refs, :qb_id,  :unique => true
    
    add_index :sales_receipt_line_refs, :sat_line_id, :unique => true
    add_index :sales_receipt_line_refs, :txn_line_id, :unique => true
  end
end
