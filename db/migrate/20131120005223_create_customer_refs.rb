class CreateCustomerRefs < ActiveRecord::Migration
  def change
    create_table :customer_refs do |t|
      t.integer :sat_id
      t.string  :qb_id, length: 30

      t.timestamps
    end
  end
end
