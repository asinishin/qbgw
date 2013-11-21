class CreateCustomerDelta < ActiveRecord::Migration
  def change
    create_table :customer_deltas do |t|
      t.string  :operation,     length: 5, null: false
      t.integer :sat_id,        null: false
      t.string  :qb_id,         length: 30
      t.integer :input_order,   null: false
      t.decimal :edit_sequence, :precision => 15, :scale => 0
      t.string  :status,        length: 5, null: false, default: 'wait'

      t.string  :first_name
      t.string  :last_name

      t.timestamps
    end
  end
end
