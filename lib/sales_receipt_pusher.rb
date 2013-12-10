class SalesReceiptPusher

  def self.add_receipt(sales_receipt)
    if StPurchase.where('sat_id = ?', sales_receipt.sat_id).first
      false
    else
      StPurchase.create(
        sat_id:          sales_receipt.sat_id,
	sat_customer_id: sales_receipt.customer_id,
	ref_number:      sales_receipt.ref_number,
	txn_date:        sales_receipt.txn_date,
	is_cashed:       sales_receipt.is_cashed,
	account_ref:     sales_receipt.account_ref
      )
    end
  end 

  def self.add_payment(sales_receipt)
    receipt = StPurchase.where('sat_id = ?', sales_receipt.sat_id).first
    if receipt
      receipt.update(
        sat_id:          sales_receipt.sat_id,
	sat_customer_id: sales_receipt.customer_id,
	ref_number:      sales_receipt.ref_number,
	txn_date:        sales_receipt.txn_date,
	is_cashed:       sales_receipt.is_cashed,
	account_ref:     sales_receipt.account_ref
      )
    else
      false
    end
  end 

  def self.delete_receipt(sales_receipt)
    purchase = StPurchase.where('sat_id = ?', sales_receipt.sat_id).first
    purchase.destroy if purchase
    purchase
  end

end
