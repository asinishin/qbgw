require 'monitor'

class ItemServicePuller

  def self.lock
    @@lock ||= Monitor.new
  end

  def self.modification_bit
    lock.synchronize do
      delta = ItemServiceBit.joins(:item_service_ref).where(
	%Q{
	  item_service_ref.edit_sequence IS NOT NULL
	  AND item_service_bits.operation = ?
	  AND item_service_bits.status = ?
	  AND NOT EXISTS (
	    SELECT 'x' FROM item_service_bits b
	    WHERE b.status = ?
	    AND b.item_service_ref_id = item_service_refs.id
	  )
	}.squish, 'upd', 'wait', 'work'
      ).order('item_service_bits.id').readonly(false).first
      delta.update_attributes(status: 'work') if delta
      delta
    end
  end

  def self.creation_bit
    lock.synchronize do
      delta = ItemServiceBit.joins(:item_service_ref).where(
	%Q{
	  item_service_refs.edit_sequence IS NULL AND
	  item_service_bits.operation = ? AND
	  item_service_bits.status = ?
	}.squish, 'add', 'wait'
      ).order('item_service_bits.id').readonly(false).first
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

end
