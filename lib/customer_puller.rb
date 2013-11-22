require 'monitor'

class CustomerPuller

  def self.lock
    @@lock ||= Monitor.new
  end

  def self.modifications
    lock.synchronize do
      CustomerBit.joins(:customer_ref).where(
	%Q{
	  customer_refs.edit_sequence IS NOT NULL AND
	  customer_bits.operation = ? AND
	  customer_bits.status = ?
	}.squish, 'upd', 'wait'
      ).order('customer_bits.input_order').readonly(false).first(10).map do |delta|
        delta.update_attributes(status: 'work')
	delta
      end
    end
  end

  def self.news
    lock.synchronize do
      CustomerBit.joins(:customer_ref).where(
	%Q{
	  customer_refs.edit_sequence IS NULL AND
	  customer_bits.operation = ? AND
	  customer_bits.status = ?
	}.squish, 'add', 'wait'
      ).order('customer_bits.id').readonly(false).first(10).map do |delta|
        delta.update_attributes(status: 'work')
	delta
      end
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
