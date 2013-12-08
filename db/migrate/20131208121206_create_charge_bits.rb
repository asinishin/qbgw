class CreateChargeBits < ActiveRecord::Migration
  def change
    create_table :charge_bits do |t|
      t.string  :operation,     length: 5, null: false
      t.string  :status,        length: 5, null: false, default: 'wait'

      t.integer :customer_id
      t.string  :ref_number
      t.string  :txn_date

      t.integer :item_id
      t.string  :quantity
      t.string  :amount
      t.integer :charge_ref_id, null: false

      t.timestamps
    end
  end
end
