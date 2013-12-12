class AddIndexToCargeRefs < ActiveRecord::Migration
  def change
    add_index :charge_refs, :sat_line_id, :unique => true
    add_index :charge_refs, :qb_id, :unique => true
  end
end
