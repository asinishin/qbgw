class SalesReceiptLinePusher

  def self.add_receipt_line(receipt_line)
    if StPurchasePackage.where('sat_line_id = ?', receipt_line.sat_line_id).first
      false
    else
      StPurchasePackage.create(
        sat_line_id: receipt_line.sat_line_id,
        sat_id:      receipt_line.sat_id,
	txn_date:    receipt_line.txn_date,
        sat_item_id: receipt_line.sat_item_id,
        quantity:    receipt_line.quantity,
        amount:      receipt_line.amount,
        class_ref:   receipt_line.class_ref
      )
    end
  end 

  def self.delete_receipt_line(receipt_line)
    line = StPurchasePackage.where('sat_line_id = ?', receipt_line.sat_line_id).first
    line.destroy if line
    line
  end

end
