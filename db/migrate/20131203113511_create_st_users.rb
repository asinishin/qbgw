class CreateStUsers < ActiveRecord::Migration
  def change
    create_table :st_users do |t|
      t.integer :sat_id, null: false
      t.string  :first_name, null: false
      t.string  :last_name, null: false
      t.string  :qb_list_id

      t.timestamps
    end
  end
end
