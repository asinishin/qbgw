class SalesReceiptPusher

  def self.add_receipt(sales_receipt)
    sales_receipt_ref = SalesReceiptRef.new(sat_id: sales_receipt.sat_id)
    sales_receipt_ref.save!
    SalesReceiptPusher::create_bit(sales_receipt, 'add', sales_receipt_ref.id)
  end 

  def self.delete_receipt(sales_receipt)
    sales_receipt_ref = SalesReceiptRef.where('sat_id = ?', sales_receipt.sat_id).first
    if sales_receipt_ref
      SalesReceiptPusher::create_bit(item, 'del', sales_receipt.id)
    else
      Rails.logger.info "Update Error: sales receipt is not found ==>#{ sales_receipt.inspect }"
    end
  end

  def self.create_bit(sales_receipt, operation, sales_receipt_ref_id)
    sales_receipt_bit = SalesReceiptBit.new(
      operation:     operation,
      customer_id:   sales_receipt.customer_id,
      ref_number:    sales_receipt.ref_number,
      txn_date:      sales_receipt.txn_date,
      sales_receipt_ref_id: sales_receipt_ref_id
    )
    sales_receipt_bit.save!

    if sales_receipt.lines
      sales_receipt.lines.each do |line|
        SalesReceiptLine.create(
	  sales_receipt_bit_id: sales_receipt_bit.id,
	  item_id:   line.item_id,
	  quantity:  line.quantity,
	  amount:    line.amount,
	  class_ref: line.class_ref
	)
      end
    end
  end

end
