class StPurchasePackage < ActiveRecord::Base
  attr_accessible :amount, :class_ref, :qb_item_ref,
                  :qb_txn_line_id, :quantity, :sat_id,
		  :sat_item_id, :sat_line_id, :txn_date
end
