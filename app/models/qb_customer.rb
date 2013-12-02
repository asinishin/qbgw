class QbCustomer < ActiveRecord::Base
  attr_accessible :first_name, :last_name, :list_id, :snapshot_id

  belongs_to :snapshot
end
