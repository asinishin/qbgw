class CreateSalesReceiptLines < ActiveRecord::Migration
  def change
    create_table :sales_receipt_lines do |t|
      t.integer :sales_receipt_bit_id, null: false
      t.integer :item_id,              null: false
      t.string  :quantity
      t.string  :amount
      t.string  :class_ref

      t.timestamps
    end
  end
end
