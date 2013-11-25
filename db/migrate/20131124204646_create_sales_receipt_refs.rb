class CreateSalesReceiptRefs < ActiveRecord::Migration
  def change
    create_table :sales_receipt_refs do |t|
      t.integer :sat_id,        null: false
      t.string  :qb_id,         length: 30
      t.decimal :edit_sequence, :precision => 15, :scale => 0

      t.timestamps
    end
  end
end
