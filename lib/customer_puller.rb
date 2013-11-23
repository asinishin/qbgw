require 'monitor'

class CustomerPuller

  def self.lock
    @@lock ||= Monitor.new
  end

  def self.modification_bit
    lock.synchronize do
      delta = CustomerBit.joins(:customer_ref).where(
	%Q{
	  customer_refs.edit_sequence IS NOT NULL
	  AND customer_bits.operation = ?
	  AND customer_bits.status = ?
	  AND NOT EXISTS (
	    SELECT 'x' FROM customer_bits b
	    WHERE b.status = ?
	    AND b.customer_ref_id = customer_refs.id
	  )
	}.squish, 'upd', 'wait', 'work'
      ).order('customer_bits.id').readonly(false).first
      delta.update_attributes(status: 'work')
      delta
    end
  end

  def self.creation_bit
    lock.synchronize do
      delta = CustomerBit.joins(:customer_ref).where(
	%Q{
	  customer_refs.edit_sequence IS NULL AND
	  customer_bits.operation = ? AND
	  customer_bits.status = ?
	}.squish, 'add', 'wait'
      ).order('customer_bits.id').readonly(false).first
      delta.update_attributes(status: 'work')
      delta
    end
  end

  def self.done(delta_id)
    lock.synchronize do
      delta = CustomerBit.where("id = #{ delta_id } AND status = 'work'").first
      if delta
        delta.update_attributes(status: 'done')
      end
      delta
    end
  end

  def self.reset(delta_id)
    lock.synchronize do
      delta = CustomerBit.where("id = #{ delta_id } AND status = 'work'").first
      if delta
        delta.update_attributes(status: 'wait')
      end
      delta
    end
  end

end
