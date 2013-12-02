class QbItemService < ActiveRecord::Base
  attr_accessible :account_ref, :list_id, :name, :snapshot_id

  belongs_to :snapshot

end
