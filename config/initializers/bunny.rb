if defined?(PhusionPassenger) # otherwise it breaks rake commands if you put this in an initializer
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked
       $q_connection = Bunny.new;
       $q_connection.start

       $q_channel = $q_connection.create_channel
       $customers_queue = $q_channel.queue("customers", :durable => true, :auto_delete => false)
    end
  end
end
