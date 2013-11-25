require 'monitor'

class SalesReceiptPuller

  def self.lock
    @@lock ||= Monitor.new
  end

  def self.removal_bit
    lock.synchronize do
      delta = SalesReceiptBit.joins(:sales_receipt_ref).where(
	%Q{
	  sales_receipt_refs.edit_sequence IS NOT NULL
	  AND sales_receipt_bits.operation = ?
	  AND sales_receipt_bits.status = ?
	  AND NOT EXISTS (
	    SELECT 'x' FROM sales_receipt_bits b
	    WHERE b.status = ?
	    AND b.sales_receipt_ref_id = sales_receipt_refs.id
	  )
	}.squish, 'del', 'wait', 'work'
      ).order('sales_receipt_bits.id').readonly(false).first
      delta.update_attributes(status: 'work') if delta
      delta
    end
  end

  def self.creation_bit
    lock.synchronize do
      delta = SalesReceiptBit.joins(:sales_receipt_ref).where(
	%Q{
	  sales_receipt_refs.edit_sequence IS NULL AND
	  sales_receipt_bits.operation = ? AND
	  sales_receipt_bits.status = ?
	}.squish, 'add', 'wait'
      ).order('sales_receipt_bits.id').readonly(false).first
      delta.update_attributes(status: 'work') if delta
      delta
    end
  end

  def self.done(delta_id)
    lock.synchronize do
      delta = SalesReceiptBit.where("id = #{ delta_id } AND status = 'work'").first
      delta.update_attributes(status: 'done') if delta
      delta
    end
  end

  def self.reset(delta_id)
    lock.synchronize do
      delta = SalesReceiptBit.where("id = #{ delta_id } AND status = 'work'").first
      delta.update_attributes(status: 'wait') if delta
      delta
    end
  end

end
