class ChargePusher

  def self.add_charge(charge)
    if StPurchasePackage.where('sat_line_id = ?', charge.sat_line_id).first
      false
    else
      StPurchasePackage.create(
        sat_id:          charge.sat_id,
	sat_customer_id: charge.customer_id,
	ref_number:      charge.ref_number,
	txn_date:        charge.txn_date,

	sat_line_id:     charge.sat_line_id,
	sat_item_id:     charge.sat_item_id,
	quantity:        charge.quantity,
        amount:          charge.amount,
	class_ref:       charge.class_ref
      )
    end
  end 

  def self.delete_charge(charge)
    charge = StPurchasePackage.where('sat_line_id = ?', charge.sat_line_id).first
    charge.destroy if charge
    charge
  end

end
