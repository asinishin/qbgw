class StPurchase < ActiveRecord::Base
  attr_accessible :account_ref, :qb_customer_list_id, :is_cashed, :ref_number,
                  :sat_customer_id, :sat_id, :txn_date
end
