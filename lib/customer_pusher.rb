class CustomerPusher

  def self.add_customer(customer)
    customer_ref = CustomerRef.new(sat_id: customer.sat_id)
    customer_ref.save!
    CustomerPusher::create_bit(customer, 'add', customer_ref.id)
  end 

  def self.modify_customer(customer)
    customer_ref = CustomerRef.where('sat_id = ?', customer.sat_id).first
    if customer_ref
      CustomerPusher::create_bit(customer, 'upd', customer_ref.id)
    else
      Rails.logger.info "Update Error: customer is not found ==>#{ customer.inspect }"
    end
  end

  def self.create_bit(customer, operation, customer_ref_id)
    customer_bit = CustomerBit.new(
      operation:   operation,
      first_name:  customer.first_name,      
      last_name:   customer.last_name,
      customer_ref_id: customer_ref_id
    )
    customer_bit.save!
  end

end
