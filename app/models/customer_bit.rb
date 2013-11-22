class CustomerBit < ActiveRecord::Base
  attr_accessible :customer_ref_id, :first_name, :input_order, :last_name, :operation, :status

  belongs_to :customer_ref

end
