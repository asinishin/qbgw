class CreateQbSalesReceiptLines < ActiveRecord::Migration
  def change
    create_table :qb_sales_receipt_lines do |t|
      t.string :txn_line_id
      t.string :item_ref
      t.string :quantity
      t.string :class_ref
      t.string :amount
      t.integer :qb_sales_receipt_id

      t.timestamps
    end
  end
end
