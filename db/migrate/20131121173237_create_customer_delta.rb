class CreateCustomerDelta < ActiveRecord::Migration
  def change
    create_table :customer_deltas do |t|
      t.string  :operation,     length: 5, null: false
      t.decimal :input_order,   null: false, :precision => 15, :scale => 0
      t.string  :status,        length: 5, null: false, default: 'wait'

      t.string  :first_name
      t.string  :last_name

      t.integer :customer_ref_id, null: false

      t.timestamps
    end
  end
end
