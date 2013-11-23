class ItemServiceBit < ActiveRecord::Base
  attr_accessible :account_ref, :description, :item_service_ref_id, :name, :operation, :status
end
