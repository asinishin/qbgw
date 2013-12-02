class CreateSnapshots < ActiveRecord::Migration
  def change
    create_table :snapshots do |t|
      t.string :status,    length: 30, null: false, default: 'start'
      t.date   :date_from, null: false
      t.date   :date_to,   null: false

      t.timestamps
    end
  end
end
