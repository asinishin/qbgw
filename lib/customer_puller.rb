require 'monitor'

class CustomerPuller

  def self.lock
    @@lock ||= Monitor.new
  end

  def self.next_bit
    lock.synchronize do
      delta = CustomerPuller::pull_next_bit
      delta.update_attributes(status: 'work') if delta
      delta
    end
  end

  def self.done(delta_id)
    lock.synchronize do
      delta = CustomerBit.where("id = #{ delta_id } AND status = 'work'").first
      delta.update_attributes(status: 'done') if delta
      delta
    end
  end

  def self.reset(delta_id)
    lock.synchronize do
      delta = CustomerBit.where("id = #{ delta_id } AND status = 'work'").first
      delta.update_attributes(status: 'wait') if delta
      delta
    end
  end
 
protected

  def self.pull_next_bit
    delta = CustomerBit.where(
      %Q{
	customer_bits.status = ?
	AND NOT EXISTS (
	  SELECT 'x' FROM customer_bits b
	  WHERE b.status = ?
	  AND b.customer_ref_id = customer_bits.customer_ref_id
	)
      }.squish, 'wait', 'work'
    ).order('customer_bits.id').first
    delta
  end
end
