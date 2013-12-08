class CreateQbCharges < ActiveRecord::Migration
  def change
    create_table :qb_charges do |t|
      t.string  :txn_id
      t.decimal :edit_sequence, :precision => 15, :scale => 0
      t.string  :ref_number
      t.string  :txn_date
      t.string  :item_ref
      t.string  :quantity
      t.string  :amount
      t.string  :class_ref
      t.integer :snapshot_id

      t.timestamps
    end
  end
end
