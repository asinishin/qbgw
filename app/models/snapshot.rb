require 'monitor'

class Snapshot < ActiveRecord::Base
  attr_accessible :status, :date_from, :date_to

  MOVES = {
    start: [ 
      :reading_items,
      :done
    ],
    reading_items: [
      :reading_items,
      :sending_items,
      :done
    ],
    sending_items: [ 
      :sending_items,
      :reading_customers,
      :done
    ],
    reading_customers: [
      :reading_customers,
      :sending_customers,
      :done
    ],
    sending_customers: [
      :sending_customers,
      :reading_sales,
      :done
    ],
    reading_sales: [
      :reading_sales,
      :sending_sales,
      :done
    ],
    sending_sales: [
      :reading_sales,
      :done
    ],
    reading_charges: [
      :reading_charges,
      :sending_charges,
      :done
    ],
    sending_charges: [
      :reading_charges,
      :done
    ]
  }

  def self.lock
    @@lock ||= Monitor.new
  end

  def self.start(date_from, date_to)
    lock.synchronize do
      curr = Snapshot.order('id').last
      unless curr && curr.status != 'done'
        curr = Snapshot.create(
	  date_from: date_from,
	  date_to:   date_to
	)
      end
      curr
    end
  end
  
  def self.current
    Snapshot.order('id').last
  end

  def self.current_status
    curr = Snapshot::current
    if curr
      curr.status.to_sym
    else
      :done
    end
  end
  
  def self.move_to(st)
    lock.synchronize do
      curr = Snapshot.order('id').last
      return false unless curr

      curr_moves = MOVES[curr.status.to_sym]
      return false unless curr_moves

      return false unless curr_moves.find(st)

      curr.update_attributes(status: st.to_s)
    end
  end

end
