require 'monitor'

class ItemServicePuller

  def self.lock
    @@lock ||= Monitor.new
  end

  def self.next_bit
    lock.synchronize do
      delta = ItemServicePuller::pull_next_bit
      delta.update_attributes(status: 'work') if delta
      delta
    end
  end

  def self.done(delta_id)
    lock.synchronize do
      delta = ItemServiceBit.where("id = #{ delta_id } AND status = 'work'").first
      delta.update_attributes(status: 'done') if delta
      delta
    end
  end

  def self.reset(delta_id)
    lock.synchronize do
      delta = ItemServiceBit.where("id = #{ delta_id } AND status = 'work'").first
      delta.update_attributes(status: 'wait') if delta
      delta
    end
  end
 
protected

  def self.pull_next_bit
    delta = ItemServiceBit.where(
      %Q{
	item_service_bits.status = ?
	AND NOT EXISTS (
	  SELECT 'x' FROM item_service_bits b
	  WHERE b.status = ?
	  AND b.item_service_ref_id = item_service_bits.item_service_ref_id
	)
      }.squish, 'wait', 'work'
    ).order('item_service_bits.id').first
    delta
  end

end
