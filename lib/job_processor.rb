require 'item_service_puller'
require 'customer_puller'
require 'sales_receipt_puller'
require 'qb_iterator'

class JobProcessor

  def self.start
    QBWC.add_job(:qb_exchange) do
      JobProcessor.qb_tick_tk
    end

    QBWC.jobs[:qb_exchange].set_response_proc do |r|
      Rails.logger.info "==> Response Callback"
      Rails.logger.info r.inspect

      JobProcessor.qb_response_tk r

    end
  end

  # Returns [Request] or nil
  def self.qb_tick_tk
    case Snapshot.current_status
    when :start
      Snapshot.move_to(:reading_items)
      JobProcessor.qb_tick_tk
    when :reading_items
      JobProcessor.wrap_request(build_select_items_request)
    when :sending_items
      request = JobProcessor.build_items_request

      if request.size == 0
        Snapshot.move_to(:reading_customers)
	JobProcessor.qb_tick_tk
      else
	JobProcessor.wrap_request(request)
      end
    when :reading_customers
      JobProcessor.wrap_request(build_select_customers_request)
    when :sending_customers
      request = JobProcessor.build_customers_request

      if request.size == 0
        Snapshot.move_to(:reading_sales)
	JobProcessor.qb_tick_tk
      else
	JobProcessor.wrap_request(request)
      end
    when :reading_sales
      JobProcessor.wrap_request(build_select_sales_request)
    when :sending_sales
      request = JobProcessor.build_sales_request

      if request.size == 0
        JobProcessor.sending_sales_end_tk
      else
	JobProcessor.wrap_request(request)
      end
    when :done
      nil
    else
      JobProcessor.error_tk("QB Tick Error, unexpected status: #{ Snapshot.current_status.to_s }")
      nil
    end
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

  def self.qb_response_tk(r)
    # Unwrap response message
    r = r['qbxml_msgs_rs'] if r['qbxml_msgs_rs']

    case Snapshot.current_status
    when :reading_items
      QbIterator.remaining_count = r['xml_attributes']['iteratorRemainingCount'].to_i
      curr = Snapshot.current

      if r['item_service_ret'] && r['item_service_ret'].respond_to?(:to_ary) 
	r['item_service_ret'].each do |item| 
	  QbItemService.create(
	    list_id:     item['list_id'],
	    name:        item['name'],
	    account_ref: item['sales_or_purchase']['account_ref']['full_name'],
	    snapshot_id: curr.id
	  )
	end
      elsif r['item_service_ret']
	QbItemService.create(
	  list_id:     r['item_service_ret']['list_id'],
	  name:        r['item_service_ret']['name'],
	  account_ref: r['item_service_ret']['sales_or_purchase']['account_ref']['full_name'],
	  snapshot_id: curr.id
	)
      end

      QbIterator.busy = false

      if QbIterator.remaining_count == 0
        JobProcessor.reading_items_end_tk
      end
    when :sending_items
      if r['item_service_ret'] || r['item_service_mod_rs'] || r['item_service_add_rs']
	JobProcessor.process_items_response(r)
      else
	JobProcessor.error_tk("Unexpected QB Response: #{ r.inspect }")
      end
    when :reading_customers
      QbIterator.remaining_count = r['xml_attributes']['iteratorRemainingCount'].to_i
      curr = Snapshot.current

      if r['customer_ret'] && r['customer_ret'].respond_to?(:to_ary) 
	r['customer_ret'].each do |cs| 
	  QbCustomer.create(
	    list_id:     cs['list_id'],
	    name:        cs['name'],
	    snapshot_id: curr.id
	  )
	end
      elsif r['customer_ret']
	QbCustomer.create(
	  list_id:     r['customer_ret']['list_id'],
	  name:        r['customer_ret']['name'],
	  snapshot_id: curr.id
	)
      end

      QbIterator.busy = false

      if QbIterator.remaining_count == 0
        JobProcessor.reading_customers_end_tk
      end
    when :sending_customers
      if r['customer_ret'] || r['customer_mod_rs'] || r['customer_add_rs']
	JobProcessor.process_customers_response(r)
      else
	JobProcessor.error_tk("Unexpected QB Response: #{ r.inspect }")
      end
    when :reading_sales
      # Here is response proc still working
      # nil
      # Or I request next portion?
      # next
    when :sending_sales
      if r['sales_receipt_ret'] || r['sales_receipt_mod_rs'] || r['sales_receipt_add_rs']
        JobProcessor.process_sales_response(r)
      else
	JobProcessor.error_tk("Unexpected QB Response: #{ r.inspect }")
      end
    else
      JobProcessor.error_tk("QB Response, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

  def self.reading_items_end_tk
    case Snapshot.current_status
    when :reading_items
      QbIterator.iterator_id = nil

      # Prepare Delta Queue for Items

      Snapshot.move_to(:sending_items)
    else
      JobProcessor.error_tk("QB reading Items, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  end

  def self.reading_customers_end_tk
    case Snapshot.current_status
    when :reading_customers
      QbIterator.iterator_id = nil

      # Prepare Delta Queue for Customers

      Snapshot.move_to(:sending_customers)
    else
      JobProcessor.error_tk("QB reading Customers, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  end

  def self.reading_sales_end_tk
    case Snapshot.current_status
    when :reading_sales

      # Prepare Delta Queue for Sales

      Snapshot.move_to(:sending_sales)
    else
      JobProcessor.error_tk("QB reading Sales Receipts, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  end

  def self.sending_sales_end_tk
    case Snapshot.current_status
    when :sending_sales

      # Email notification

      Snapshot.move_to(:done)
      nil
    else
      JobProcessor.error_tk("QB sending Sales Receipts, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  end

  def self.error_tk(err_msg)
    Rails.logger.info(err_msg)
    
    # Email notification

    Snapshot.move_to(:done)
    nil
  end

  def self.wrap_request(r)
    return nil unless r

    r.merge!({ :xml_attributes => { "onError" => "stopOnError" } })
    [r]
  end

  def self.iterator_not_ready?
    QbIterator.busy? || (QbIterator.iterator_id && QbIterator.remaining_count == 0)
  end

  def self.prepare_iterator
    QbIterator.busy = true

    attrs = {
      "requestID" => QbIterator.request_id,
      "iterator"  => QbIterator.iterator_id.nil? ? "Start" : "Continue"
    }
    unless QbIterator.iterator_id.nil? # Start iterations?
      attrs.merge!(
        "iteratorID" => QbIterator.iterator_id
      )
    end
    attrs
  end

  def self.build_select_items_request
    return nil if JobProcessor.iterator_not_ready?

    attrs = JobProcessor.prepare_iterator

    {
      :item_service_query_rq => {
	:xml_attributes => attrs,
	:max_returned => 20,
	:owner_id => 0
      }
    }
  end

  def self.build_select_customers_request
    return nil if JobProcessor.iterator_not_ready?

    attrs = JobProcessor.prepare_iterator

    {
      :customer_query_rq => {
	:xml_attributes => attrs,
	:max_returned => 20,
	:owner_id => 0
      }
    }
  end

  def self.build_select_sales_request
    return nil if JobProcessor.iterator_not_ready?

    Rails.logger.info "Here we are ever ==>"

    attrs = JobProcessor.prepare_iterator

    {
      :sales_receipt_query_rq => {
	:xml_attributes => attrs,
	:max_returned => 20,
	:include_line_items => 1
      }
    }
  end

  def self.build_items_request
    bits = []
    10.times.each do
      delta = ItemServicePuller.next_bit
      break if delta.nil?

      bits << delta
    end

    if bits.size == 0
      return {}
    end

    request = {}
    mods = bits.select { |v| v.operation == 'upd' }
    if mods.size > 0
      request.merge!( 
	:item_service_mod_rq => mods.map do |delta|
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :item_service_mod   => {
	      :list_id       => delta.item_service_ref.qb_id,
	      :edit_sequence => delta.item_service_ref.edit_sequence,
	      :name          => delta.name,
	      :sales_or_purchase_mod => {
		:desc => delta.description,
		:account_ref => { full_name: delta.account_ref }
	      }
	    }
	  }
	end 
      )
    end

    news = bits.select { |v| v.operation == 'add' }
    if news.size > 0
      request.merge!( 
	:item_service_add_rq => news.map do |delta|
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :item_service_add => {
	      :name      => delta.name,
	      :sales_or_purchase => {
		:desc => delta.description,
		:price => '0.0',
		:account_ref => { full_name: delta.account_ref }
	      }
	    }
	  }
	end
      )
    end
    request
  end

  def self.build_customers_request
    bits = []
    10.times.each do
      delta = CustomerPuller.next_bit
      break if delta.nil?

      bits << delta
    end

    if bits.size == 0
      return {}
    end

    request = {}
    mods = bits.select { |v| v.operation == 'upd' }
    if mods.size > 0
      request.merge!( 
	:customer_mod_rq => mods.map do |delta|
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :customer_mod   => {
	      :list_id       => delta.customer_ref.qb_id,
	      :edit_sequence => delta.customer_ref.edit_sequence,
	      :name          => delta.first_name + ' ' + delta.last_name,
	      :first_name    => delta.first_name,
	      :last_name     => delta.last_name
	    }
	  }
	end 
      )
    end

    news = bits.select { |v| v.operation == 'add' }
    if news.size > 0
      request.merge!( 
	:customer_add_rq => news.map do |delta|
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :customer_add   => {
	      :name       => delta.first_name + ' ' + delta.last_name,
	      :first_name => delta.first_name,
	      :last_name  => delta.last_name
	    }
	  }
	end
      )
    end
    request
  end

  def self.build_sales_request
    bits = []
    10.times.each do
      delta = SalesReceiptPuller.next_bit
      break if delta.nil?

      bits << delta
    end

    if bits.size == 0
      return {}
    end

    request = {}
    dels = bits.select { |v| v.operation == 'del' }
    if dels.size > 0
      request.merge!( 
	:txn_del_rq => dels.map do |delta|
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :txn_del_type   => "SalesReceipt",
	    :txn_id => delta.sales_receipt_ref.qb_id
	  }
	end 
      )
    end

    news = bits.select { |v| v.operation == 'add' }
    if news.size > 0
      request.merge!( 
	:sales_receipt_add_rq => news.map do |delta|
	  customer = CustomerRef.where("sat_id = #{ delta.customer_id }").first
	  customer_ref = customer.qb_id if customer
	  lines = delta.sales_receipt_lines 
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :sales_receipt_add => {
	      :customer_ref => { list_id: customer_ref },
	      :ref_number => delta.ref_number,
	      :txn_date   => delta.txn_date,
	      :sales_receipt_line_add => lines.map do |line|
		item = ItemServiceRef.where("sat_id = #{ line.item_id }").first
		item_ref = item.qb_id if item
		{
		  :item_ref  => { list_id: item_ref },
		  :quantity  => line.quantity,
		  :amount    => line.amount,
		  :class_ref => { full_name: line.class_ref }
		}
	      end
	    }
	  }
	end
      )
    end
    request
  end

  def self.process_items_response_item(r)
    delta = nil
    item_service_ref = nil
    if r['xml_attributes']['requestID']
      delta = ItemServiceBit.where(
	"id = #{ r['xml_attributes']['requestID'] } AND status = 'work'"
      ).first
      item_service_ref = delta.item_service_ref if delta
    end
    if delta && r['item_service_ret'] && r['item_service_ret']['edit_sequence']
      edit_sequence = r['item_service_ret']['edit_sequence']
      ItemServiceRef.update_all(
	"edit_sequence = #{ edit_sequence }",
	"id = #{ item_service_ref.id } AND (edit_sequence < #{ edit_sequence } OR edit_sequence IS NULL)"
      )
    end
    if delta && r['xml_attributes']['statusCode'] == '0' && delta.operation == 'add'
      item_service_ref.update_attribute(:qb_id, r['item_service_ret']['list_id'])
    end
    if r['xml_attributes']['statusCode'] != '0'
      Rails.logger.info "Error: Quickbooks returned an error ==>"
      Rails.logger.info r.inspect
      ItemServicePuller.reset(delta.id) if delta
    else
      ItemServicePuller.done(delta.id) if delta
    end
    if delta.nil?
      Rails.logger.info "Error: Quickbooks request is not found ==>"
      Rails.logger.info r.inspect
    end
  end

  def self.process_items_response(r)
    # ItemServiceModRs array case
    if r['item_service_mod_rs'].respond_to?(:to_ary)
      r['item_service_mod_rs'].each{ |item| JobProcessor.process_items_response_item item }
    # Or one item
    elsif r['item_service_mod_rs']
      JobProcessor.process_items_response_item r['item_service_mod_rs']
    end

    # ItemServiceAddRs array case
    if r['item_service_add_rs'].respond_to?(:to_ary)
      r['item_service_add_rs'].each{ |item| JobProcessor.process_items_response_item item }
    # Or one item
    elsif r['item_service_add_rs']
      JobProcessor.process_items_response_item r['item_service_add_rs']
    end

    # Single request case
    if r['item_service_ret'] && r['xml_attributes']['requestID']
      JobProcessor.process_items_response_item r
    end
  end

  def self.process_customers_response_item(r)
    delta = nil
    customer_ref = nil
    if r['xml_attributes']['requestID']
      delta = CustomerBit.where(
	"id = #{ r['xml_attributes']['requestID'] } AND status = 'work'"
      ).first
      customer_ref = delta.customer_ref if delta
    end
    if delta && r['customer_ret'] && r['customer_ret']['edit_sequence']
      edit_sequence = r['customer_ret']['edit_sequence']
      CustomerRef.update_all(
	"edit_sequence = #{ edit_sequence }",
	"id = #{ customer_ref.id } AND (edit_sequence < #{ edit_sequence } OR edit_sequence IS NULL)"
      )
    end
    if delta && r['xml_attributes']['statusCode'] == '0' && delta.operation == 'add'
      customer_ref.update_attribute(:qb_id, r['customer_ret']['list_id'])
    end
    if r['xml_attributes']['statusCode'] != '0'
      Rails.logger.info "Error: Quickbooks returned an error ==>"
      Rails.logger.info r.inspect
      CustomerPuller.reset(delta.id) if delta
    else
      CustomerPuller.done(delta.id) if delta
    end
    if delta.nil?
      Rails.logger.info "Error: Quickbooks request is not found ==>"
      Rails.logger.info r.inspect
    end
  end

  def self.process_customers_response(r)
    # CustomerModRs array case
    if r['customer_mod_rs'].respond_to?(:to_ary)
      r['customer_mod_rs'].each{ |item| JobProcessor.process_customers_response_item item }
    # Or one item
    elsif r['customer_mod_rs']
      JobProcessor.process_customers_response_item r['customer_mod_rs']
    end

    # CustomerAddRs array case
    if r['customer_add_rs'].respond_to?(:to_ary)
      r['customer_add_rs'].each{ |item| JobProcessor.process_customers_response_item item }
    # Or one item
    elsif r['customer_add_rs']
      JobProcessor.process_customers_response_item r['customer_add_rs']
    end

    # Single request case
    if r['customer_ret'] && r['xml_attributes']['requestID']
      JobProcessor.process_customers_response_item r
    end
  end

  def self.process_sales_response_item(r)
    delta = nil
    sales_receipt_ref = nil
    if r['xml_attributes']['requestID']
      delta = SalesReceiptBit.where(
	"id = #{ r['xml_attributes']['requestID'] } AND status = 'work'"
      ).first
      sales_receipt_ref = delta.sales_receipt_ref if delta
    end
    if delta && r['sales_receipt_ret'] && r['sales_receipt_ret']['edit_sequence']
      edit_sequence = r['sales_receipt_ret']['edit_sequence']
      SalesReceiptRef.update_all(
	"edit_sequence = #{ edit_sequence }",
	"id = #{ sales_receipt_ref.id } AND (edit_sequence < #{ edit_sequence } OR edit_sequence IS NULL)"
      )
    end
    if delta && r['xml_attributes']['statusCode'] == '0' && delta.operation == 'add'
      sales_receipt_ref.update_attribute(:qb_id, r['sales_receipt_ret']['txn_id'])
    end
    if delta && r['xml_attributes']['statusCode'] == '0' && delta.operation == 'del'
      sales_receipt_ref.update_attributes(qb_id: nil, edit_sequence: nil)
    end
    if r['xml_attributes']['statusCode'] != '0'
      Rails.logger.info "Error: Quickbooks returned an error ==>"
      Rails.logger.info r.inspect
      SalesReceiptPuller.reset(delta.id) if delta
    else
      SalesReceiptPuller.done(delta.id) if delta
    end
    if delta.nil?
      Rails.logger.info "Error: Quickbooks request is not found ==>"
      Rails.logger.info r.inspect
    end
  end

  def self.process_sales_response(r)
    # TxnDelRs array case 
    if r['txn_del_rs'].respond_to?(:to_ary)
      r['txn_del_rs'].each{ |item| JobProcessor.process_sales_response_item item }
    # Or one item
    elsif r['txn_del_rs']
      JobProcessor.process_sales_response_item r['txn_del_rs']
    end

    # SalesReceiptAddRs array case
    if r['sales_receipt_add_rs'].respond_to?(:to_ary)
      r['sales_receipt_add_rs'].each{ |item| JobProcessor.process_sales_response_item item }
    # Or one item
    elsif r['sales_receipt_add_rs']
      JobProcessor.process_sales_response_item r['sales_receipt_add_rs']
    end

    # Single request case
    if r['sales_receipt_ret'] && r['xml_attributes']['requestID']
      JobProcessor.process_sales_response_item r
    end
  end

end
