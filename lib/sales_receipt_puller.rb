require 'monitor'

class SalesReceiptPuller

  def self.lock
    @@lock ||= Monitor.new
  end

  def self.next_bit(op)
    lock.synchronize do
      delta = SalesReceiptPuller::pull_next_bit
      if delta && delta.operation == op
	delta.update_attributes(status: 'work')
	delta
      else
        nil
      end
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
 
protected

  def self.pull_next_bit
    delta = SalesReceiptBit.where(
      %Q{
	sales_receipt_bits.status = ?
	AND NOT EXISTS (
	  SELECT 'x' FROM sales_receipt_bits b
	  WHERE b.status = ?
	  AND b.sales_receipt_ref_id = sales_receipt_bits.sales_receipt_ref_id
	)
      }.squish, 'wait', 'work'
    ).order('sales_receipt_bits.id').first
    delta
  end

end
