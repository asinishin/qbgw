class CreateStPurchasePackages < ActiveRecord::Migration
  def change
    create_table :st_purchase_packages do |t|
      t.integer :sat_id,      null: false
      t.integer :sat_customer_id, null: false
      t.string  :ref_number,  null: false
      t.string  :txn_date,    null: false

      t.integer :sat_line_id, null: false
      t.string  :qb_txn_id

      t.integer :sat_item_id, null: false
      t.string  :qb_item_ref

      t.string  :quantity,    null: false
      t.string  :amount,      null: false
      t.string  :class_ref,   null: false

      t.timestamps
    end
  end
end
