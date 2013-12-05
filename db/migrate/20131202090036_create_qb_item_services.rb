class CreateQbItemServices < ActiveRecord::Migration
  def change
    create_table :qb_item_services do |t|
      t.string  :list_id
      t.decimal :edit_sequence, :precision => 15, :scale => 0
      t.string  :name
      t.string  :description
      t.string  :account_ref
      t.integer :snapshot_id, null: false

      t.timestamps
    end
  end
end
