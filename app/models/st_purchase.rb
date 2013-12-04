class StPurchase < ActiveRecord::Base
  attr_accessible :qb_customer_list_id, :ref_number, :sat_customer_id, :sat_id, :txn_date
end
