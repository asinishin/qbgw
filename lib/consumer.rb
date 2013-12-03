class Consumer

  def self.proc_item_service(delivery_info, metadata, payload)
    item_service = ItemServiceBeef.decode(payload)
    Rails.logger.info "Item service pushed ==> #{ item_service.operation }"
    if item_service.operation == 'add'
      unless ItemServicePusher.add_item(item_service)
	Rails.logger.info "StPackage Add Error: ==>#{ item_service.inspect }"
      end
    elsif item_service.operation == 'upd'
      unless ItemServicePusher.modify_item(item_service)
	Rails.logger.info "StPackage Upd Error: ==>#{ item_service.inspect }"
      end
    elsif item_service.operation == 'dmp'
      unless ItemServicePusher.modify_item(item_service)
	ItemServicePusher.add_item(item_service)
      end
    end
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

end
