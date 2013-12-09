require 'monitor'

class ChargePuller

  def self.lock
    @@lock ||= Monitor.new
  end

  def self.next_bit
    lock.synchronize do
      delta = ChargePuller.pull_next_bit
      delta.update_attributes(status: 'work') if delta
      delta
    end
  end

  def self.done(delta_id)
    lock.synchronize do
      delta = ChargeBit.where("id = #{ delta_id } AND status = 'work'").first
      delta.update_attributes(status: 'done') if delta
      delta
    end
  end

  def self.reset(delta_id)
    lock.synchronize do
      delta = ChargeBit.where("id = #{ delta_id } AND status = 'work'").first
      delta.update_attributes(status: 'wait') if delta
      delta
    end
  end
 
protected

  def self.pull_next_bit
    delta = ChargeBit.where(
      %Q{
	charge_bits.status = ?
	AND NOT EXISTS (
	  SELECT 'x' FROM charge_bits b
	  WHERE b.status = ?
	  AND b.charge_ref_id = charge_bits.charge_ref_id
	)
      }.squish, 'wait', 'work'
    ).order('charge_bits.id').first
    delta
  end

end
