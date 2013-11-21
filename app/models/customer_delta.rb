class CustomerDelta < ActiveRecord::Base
  attr_accessible :edit_sequence, :first_name, :input_order, :last_name, :operation, :qb_id, :sat_id, :status
end
