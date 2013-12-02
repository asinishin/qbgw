class CreateQbItemServices < ActiveRecord::Migration
  def change
    create_table :qb_item_services do |t|
      t.string  :list_id
      t.string  :name
      t.string  :account_ref
      t.integer :snapshot_id, null: false

      t.timestamps
    end
  end
end
