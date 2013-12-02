class QbIterator

  def self.iterator_id
    @@iterator_id ||= nil
  end
 
  def self.iterator_id=(uid)
    @@iterator_id = uid
  end

  def self.remaining_count
    @@remainign_count ||= 0
  end

  def self.remaining_count=(count)
    @@remainign_count = count
  end

  def self.request_id
    @@request_id ||= 1
  end

  def self.request_id=(new_id)
    @@request_id = 1
  end

  def self.busy?
    @@busy ||= false
  end

  def self.busy=(is_busy)
    @@busy = is_busy
  end

end
