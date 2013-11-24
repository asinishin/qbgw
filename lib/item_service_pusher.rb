class ItemServicePusher

  def self.add_item(item)
    item_service_ref = ItemServiceRef.new(sat_id: item.sat_id)
    item_service_ref.save!
    ItemServicePusher::create_bit(item, 'add', item_service_ref.id)
  end 

  def self.modify_item(item)
    item_service_ref = ItemServiceRef.where('sat_id = ?', item.sat_id).first
    if item_service_ref
      ItemServicePusher::create_bit(item, 'upd', item_service_ref.id)
    else
      Rails.logger.info "Update Error: item service is not found ==>#{ item.inspect }"
    end
  end

  def self.create_bit(item, operation, item_service_ref_id)
    item_service_bit = ItemServiceBit.new(
      operation:     operation,
      name:          item.name,      
      description:   item.description,
      account_ref:   item.account_ref,
      item_service_ref_id: item_service_ref_id
    )
    item_service_bit.save!
  end

end
