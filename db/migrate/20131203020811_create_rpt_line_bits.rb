class CreateRptLineBits < ActiveRecord::Migration
  def change
    create_table :sales_receipt_line_bits do |t|
      t.string  :operation,            null: false
      t.integer :item_id,              null: false
      t.string  :quantity
      t.string  :amount
      t.string  :class_ref
      t.integer :sales_receipt_line_refs, null: false
      t.integer :sales_receipt_bit_id,    null: false

      t.timestamps
    end
  end
end
