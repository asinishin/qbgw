require 'batch_beef'
require 'customer_beef'
require 'customer_pusher'
require 'item_service_beef'
require 'item_service_pusher'
require 'charge_beef'
require 'charge_pusher'

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

  def self.proc_charge(delivery_info, metadata, payload)
    charge = ChargeBeef.decode(payload)
    Rails.logger.info "Charge pushed ==> #{ charge.operation }"
    if charge.operation == 'add'
      unless ChargePusher.add_charge(charge)
	Rails.logger.info "StPurchasePackage Add Error: ==>#{ charge.inspect }"
      end
    elsif charge.operation == 'del'
      unless ChargePusher.delete_charge(charge)
	Rails.logger.info "StPurchasePackage Del Error: ==>#{ charge.inspect }"
      end
    elsif charge.operation == 'dmp'
      ChargePusher.add_charge(charge)
    end
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

  def self.proc_control(delivery_info, metadata, payload)
    batch = BatchBeef.decode(payload)
    Rails.logger.info "Sales batch pushed ==> "

    # Reset all running batches
    Snapshot.update_all("status = 'done'", "status != 'done'")

    Snapshot.create(
      date_from: batch.date_from,
      date_to:   batch.date_to
    )
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end
end
