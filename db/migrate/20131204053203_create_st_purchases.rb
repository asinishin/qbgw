class CreateStPurchases < ActiveRecord::Migration
  def change
    create_table :st_purchases do |t|
      t.integer :sat_id, null: false
      t.integer :sat_customer_id, null: false
      t.string  :ref_number, null: false
      t.string  :txn_date, null: false
      t.boolean :is_cashed, null: false
      t.string  :qb_customer_list_id

      t.timestamps
    end
  end
end
