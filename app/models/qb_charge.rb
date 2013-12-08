class QbCharge < ActiveRecord::Base
  attr_accessible :amount, :class_ref, :edit_sequence, :quantity,
                  :item_ref, :ref_number, :snapshot_id, :txn_date, :txn_id
end
