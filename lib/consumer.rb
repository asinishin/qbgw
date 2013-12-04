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

  def self.proc_customer(delivery_info, metadata, payload)
    customer = CustomerBeef.decode(payload)
    Rails.logger.info "Customer pushed ==> #{ customer.operation }"
    if customer.operation == 'add'
      unless CustomerPusher.add_customer(customer)
	Rails.logger.info "StPackage Add Error: ==>#{ customer.inspect }"
      end
    elsif customer.operation == 'upd'
      unless CustomerPusher.modify_customer(customer)
	Rails.logger.info "StPackage Upd Error: ==>#{ customer.inspect }"
      end
    elsif customer.operation == 'dmp'
      unless CustomerPusher.modify_customer(customer)
	CustomerPusher.add_customer(customer)
      end
    end
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

  def self.proc_sales_receipt(delivery_info, metadata, payload)
    sales_receipt = SalesReceiptBeef.decode(payload)
    Rails.logger.info "Sales receipt pushed ==> #{ sales_receipt.operation }"
    if sales_receipt.operation == 'add'
      unless SalesReceiptPusher.add_receipt(sales_receipt)
	Rails.logger.info "StPurchase Add Error: ==>#{ sales_receipt.inspect }"
      end
    elsif sales_receipt.operation == 'del'
      unless SalesReceiptPusher.delete_receipt(sales_receipt)
	Rails.logger.info "StPurchase Del Error: ==>#{ sales_receipt.inspect }"
      end
    elsif sales_receipt.operation == 'dmp'
     # unless CustomerPusher.modify_customer(customer)
     #	CustomerPusher.add_customer(customer)
     # end
    end
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

  def self.proc_sales_receipt_line(delivery_info, metadata, payload)
    receipt_line = SalesReceiptLineBeef.decode(payload)
    Rails.logger.info "Sales receipt pushed ==> #{ receipt_line.operation }"
    if receipt_line.operation == 'add'
      unless SalesReceiptLinePusher.add_receipt_line(receipt_line)
	Rails.logger.info "StPurchasePackage Add Error: ==>#{ receipt_line.inspect }"
      end
    elsif receipt_line.operation == 'del'
      unless SalesReceiptLinePusher.delete_receipt_line(receipt_line)
	Rails.logger.info "StPurchasePackage Del Error: ==>#{ receipt_line.inspect }"
      end
    elsif receipt_line.operation == 'dmp'
     # unless CustomerPusher.modify_customer(customer)
     #	CustomerPusher.add_customer(customer)
     # end
    end
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

end
