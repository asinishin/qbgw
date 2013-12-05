class QbCustomer < ActiveRecord::Base
  attr_accessible :name, :edit_sequence, :list_id, :snapshot_id

  belongs_to :snapshot
end
