require 'consumer'

if defined?(PhusionPassenger) # otherwise it breaks rake commands if you put this in an initializer
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked
      q_connection = Bunny.new;
      q_connection.start

      q_channel = q_connection.create_channel
      customers_queue = q_channel.queue("customers", :durable => true, :auto_delete => false)

      customers_queue.subscribe do |delivery_info, metadata, payload|
        Consumer.proc_customer(delivery_info, metadata, payload)
      end

      item_services_queue = q_channel.queue("item_services", :durable => true, :auto_delete => false)

      item_services_queue.subscribe do |delivery_info, metadata, payload|
        Consumer.proc_item_service(delivery_info, metadata, payload)
      end

      charges_queue = q_channel.queue("charges", :durable => true, :auto_delete => false)

      charges_queue.subscribe do |delivery_info, metadata, payload|
        Consumer.proc_charge(delivery_info, metadata, payload)
      end

      control_queue = q_channel.queue("control", :durable => true, :auto_delete => false)

      control_queue.subscribe do |delivery_info, metadata, payload|
        Consumer.proc_control(delivery_info, metadata, payload)
      end

      $q_tick = 0
    end
  end
end
