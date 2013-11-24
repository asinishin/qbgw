require 'customer_beef'
require 'customer_pusher'

if defined?(PhusionPassenger) # otherwise it breaks rake commands if you put this in an initializer
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked
      q_connection = Bunny.new;
      q_connection.start

      q_channel = q_connection.create_channel
      customers_queue = q_channel.queue("customers", :durable => true, :auto_delete => false)

      customers_queue.subscribe do |delivery_info, metadata, payload|
	customer = CustomerBeef.decode(payload)
	Rails.logger.info "Here Push operation ==> #{ customer.operation }"
	if customer.operation == 'add'
	  CustomerPusher.add_customer(customer)
	else # update operation
	  CustomerPusher.modify_customer(customer)
	end
      end

      item_services_queue = q_channel.queue("item_services", :durable => true, :auto_delete => false)

      item_services_queue.subscribe do |delivery_info, metadata, payload|
	item_service = ItemServiceBeef.decode(payload)
	Rails.logger.info "Here Push operation ==> #{ item_service.operation }"
	if item_service.operation == 'add'
	  ItemServicePusher.add_item(item_service)
	else # update operation
	  ItemServicePusher.modify_item(item_service)
	end
      end

      $q_tick = 0
    end
  end
end
