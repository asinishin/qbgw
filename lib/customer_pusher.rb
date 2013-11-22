class CustomerPusher

  def self.add_customer(customer)
    customer_ref = CustomerRef.new(sat_id: customer.sat_id, input_order: 1)
    customer_ref.save!
    customer_bit = CustomerBit.new(
      operation:   'add',
      input_order: 0,
      first_name:  customer.first_name,      
      last_name:   customer.last_name,
      customer_ref_id: customer_ref.id
    )
    customer_bit.save!
  end 

  def self.modify_customer(customer)
    customer_ref = CustomerRef.where('sat_id = ?', customer.sat_id).first
    if customer_ref
      customer_bit = CustomerBit.new(
	operation:   'upd',
	input_order: customer_ref.input_order,
	first_name:  customer.first_name,      
	last_name:   customer.last_name,
	customer_ref_id: customer_ref.id
      )
      customer_bit.save!

      CustomerRef.update_all(
	"input_order = input_order + 1",
	"id = #{ customer_ref.id }"
      )
    else
      Rails.logger.info "Update Error: customer is not found ==>#{ customer.inspect }"
    end
  end

end
