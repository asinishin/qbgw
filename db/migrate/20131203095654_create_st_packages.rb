class CreateStPackages < ActiveRecord::Migration
  def change
    create_table :st_packages do |t|
      t.string  :name,   null: false
      t.string  :description
      t.integer :sat_id, null: false
      t.string  :qb_list_id
      t.string  :account_ref, null: false

      t.timestamps
    end
  end
end
