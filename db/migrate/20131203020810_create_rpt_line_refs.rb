class CreateRptLineRefs < ActiveRecord::Migration
  def change
    create_table :sales_receipt_line_refs do |t|
      t.integer :sat_line_id, null: false
      t.string  :txn_line_id
      t.integer :salece_receipt_ref_id, null: false

      t.timestamps
    end
  end
end
