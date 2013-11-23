class CreateItemServiceBits < ActiveRecord::Migration
  def change
    create_table :item_service_bits do |t|
      t.string  :operation,     length: 5, null: false
      t.string  :status,        length: 5, null: false, default: 'wait'

      t.string  :name
      t.string  :description
      t.string  :account_ref

      t.integer :item_service_ref_id, null: false

      t.timestamps
    end
  end
end
