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

      sales_queue = q_channel.queue("sales", :durable => true, :auto_delete => false)

      sales_queue.subscribe do |delivery_info, metadata, payload|
        Consumer.proc_sales_receipt(delivery_info, metadata, payload)
      end

      sale_lines_queue = q_channel.queue("sale_lines", :durable => true, :auto_delete => false)

      sale_lines_queue.subscribe do |delivery_info, metadata, payload|
        Consumer.proc_sales_receipt_line(delivery_info, metadata, payload)
      end

      $q_tick = 0
    end
  end
end
