require 'monitor'

class Snapshot < ActiveRecord::Base
  attr_accessible :status, :date_from, :date_to

  MOVES = {
    start: {
      qb_tick:               :reading_items
    },
    reading_items: {
      qb_tick:               :reading_items,
      qb_response:           :reading_items,
      reading_items_end:     :sending_items,
      error:                 :done
    },
    sending_items: {
      qb_tick:               :sending_items,
      qb_response:           :sending_items,
      sending_items_end:     :reading_customers,
      error:                 :done
    },
    reading_customers: {
      qb_tick:               :reading_customers,
      qb_response:           :reading_customers,
      reading_customers_end: :sending_customers,
      error:                 :done
    },
    sending_customers: {
      qb_tick:               :sending_customers,
      qb_response:           :sending_customers,
      sending_customers_end: :reading_sales,
      error:                 :done
    },
    reading_sales: {
      qb_tick:               :reading_sales,
      qb_response:           :reading_sales,
      reading_sales_end:     :sending_sales,
      error:                 :done
    },
    sending_sales: {
      qb_tick:               :reading_sales,
      qb_response:           :reading_sales,
      sending_sales_end:     :done,
      error:                 :done
    }
  }

  def self.lock
    @@lock ||= Monitor.new
  end

  def self.start
    lock.synchronize do
      curr = Snapshot.order('id').last
      unless curr && curr.status != 'done'
        curr = Snapshot.create
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
      return nil unless curr

      curr_moves = MOVES[curr.status.to_sym]
      return nil unless curr_moves

      move = curr_moves[st]
      return nil unless move

      curr.update_attributes(status: move.to_s)
      curr.status.to_sym
    end
  end

end
