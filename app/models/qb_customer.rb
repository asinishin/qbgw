class QbCustomer < ActiveRecord::Base
  attr_accessible :name, :list_id, :snapshot_id

  belongs_to :snapshot
end
