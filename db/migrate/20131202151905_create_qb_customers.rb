class CreateQbCustomers < ActiveRecord::Migration
  def change
    create_table :qb_customers do |t|
      t.string  :list_id
      t.string  :first_name
      t.string  :last_name
      t.integer :snapshot_id

      t.timestamps
    end
  end
end
