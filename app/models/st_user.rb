class StUser < ActiveRecord::Base
  attr_accessible :first_name, :last_name, :qb_list_id, :sat_id
end
