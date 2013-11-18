if defined?(PhusionPassenger) # otherwise it breaks rake commands if you put this in an initializer
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked
       # We’re in a smart spawning mode
       # Now is a good time to connect to RabbitMQ
       $rabbitmq_connection = Bunny.new;
       $rabbitmq_connection.start

       $rabbitmq_channel    = $rabbitmq_connection.create_channel
       $rabbitmq_queue      = $rabbitmq_channel.queue("quickbooks", :durable => true, :auto_delete => false)
    end
  end
end
