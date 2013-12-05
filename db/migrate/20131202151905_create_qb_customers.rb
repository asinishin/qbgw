class CreateQbCustomers < ActiveRecord::Migration
  def change
    create_table :qb_customers do |t|
      t.string  :list_id
      t.decimal :edit_sequence, :precision => 15, :scale => 0
      t.string  :name
      t.integer :snapshot_id

      t.timestamps
    end
  end
end
