class ChargeBit < ActiveRecord::Base
  attr_accessible :amount, :charge_ref_id, :customer_id, :item_id, :operation,
                  :quantity, :ref_number, :status, :txn_date
end
