class CustomerPusher

  def self.add_customer(customer)
    if StUser.where('sat_id = ?', customer.sat_id).first
      false
    else
      StUser.create(
        first_name:  customer.first_name,
        last_name:   customer.last_name,
        sat_id:      customer.sat_id
      )
    end
  end 

  def self.modify_customer(customer)
    user = StUser.where('sat_id = ?', customer.sat_id).first
    if user
      user.update_attributes(
        first_name:  customer.first_name,
        last_name:   customer.last_name
      )
    else
      false
    end
  end

end
