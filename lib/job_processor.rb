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
      # Prepare iterator for reading
      QbIterator.iterator_id = nil
      Snapshot.move_to(:reading_items)
      JobProcessor.qb_tick_tk
    when :reading_items
      JobProcessor.wrap_request(build_select_items_request)
    when :sending_items
      request = JobProcessor.build_items_request

      if request.size == 0
	# Prepare iterator for reading
	QbIterator.iterator_id = nil
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
	# Prepare iterator for reading
	QbIterator.iterator_id = nil
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
	    list_id:       item['list_id'],
	    edit_sequence: item['edit_sequence'],
	    name:          item['name'],
	    description:   item['sales_or_purchase']['desc'],
	    account_ref:   item['sales_or_purchase']['account_ref']['full_name'],
	    snapshot_id:   curr.id
	  )
	end
      elsif r['item_service_ret']
	QbItemService.create(
	  list_id:       r['item_service_ret']['list_id'],
	  edit_sequence: r['item_service_ret']['edit_sequence'],
	  name:          r['item_service_ret']['name'],
	  description:   r['item_service_ret']['sales_or_purchase']['desc'],
	  account_ref:   r['item_service_ret']['sales_or_purchase']['account_ref']['full_name'],
	  snapshot_id:   curr.id
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
	    list_id:       cs['list_id'],
	    edit_sequence: cs['edit_sequence'],
	    name:          cs['name'],
	    snapshot_id:   curr.id
	  )
	end
      elsif r['customer_ret']
	QbCustomer.create(
	  list_id:       r['customer_ret']['list_id'],
	  edit_sequence: r['customer_ret']['edit_sequence'],
	  name:          r['customer_ret']['name'],
	  snapshot_id:   curr.id
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
      QbIterator.remaining_count = r['xml_attributes']['iteratorRemainingCount'].to_i
      curr = Snapshot.current

      if r['sales_receipt_ret'] && r['sales_receipt_ret'].respond_to?(:to_ary) 
	r['sales_receipt_ret'].each do |rct| 
	  JobProcessor.store_qb_receipt_lines(rct,
	    QbSalesReceipt.create(
	      txn_id:      rct['txn_id'],
	      ref_number:  rct['ref_number'],
	      txn_date:    rct['txn_date'],
	      snapshot_id: curr.id
	    )
	  )
	end
      elsif r['sales_receipt_ret']
	JobProcessor.store_qb_receipt_lines(r['sales_receipt_ret'],
	  QbSalesReceipt.create(
	    txn_id:      r['sales_receipt_ret']['txn_id'],
	    ref_number:  r['sales_receipt_ret']['ref_number'],
	    txn_date:    r['sales_receipt_ret']['txn_date'],
	    snapshot_id: curr.id
	  )
	)
      end

      QbIterator.busy = false

      if QbIterator.remaining_count == 0
        JobProcessor.reading_sales_end_tk
      end
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
      # Prepare Delta Queue for Items
      snapshot = Snapshot.current

      StPackage.order('sat_id').each do |item|
        qb_item = nil

	item_ref = ItemServiceRef.where("sat_id = #{ item.sat_id }").first
        item_ref = ItemServiceRef.create(sat_id: item.sat_id) unless item_ref

	if item_ref.qb_id
	  qb_item = QbItemService.where(
	    "list_id = '#{ item_ref.qb_id }' AND snapshot_id = #{ snapshot.id }"
	  ).first
	else
	  qb_item = QbItemService.where(
	    "name = '#{ item.name }' AND snapshot_id = #{ snapshot.id }"
	  ).first
	end

	if qb_item
	  item_ref.update_attributes(
	    edit_sequence: qb_item.edit_sequence,
	    qb_id:         qb_item.list_id
	  )

	  unless qb_item.name == item.name && \
	         qb_item.description == item.description && \
		 qb_item.account_ref == item.account_ref
	    ItemServiceBit.create(
	      operation:   'upd',
	      name:        item.name,
	      description: item.description,
	      account_ref: item.account_ref,
	      item_service_ref_id: item_ref.id
	    )
	  end
	else
	  ItemServiceBit.create(
	    operation:   'add',
	    name:        item.name,
	    description: item.description,
	    account_ref: item.account_ref,
	    item_service_ref_id: item_ref.id
	  )
	end
      end

      Snapshot.move_to(:sending_items)
    else
      JobProcessor.error_tk("QB reading Items, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  end

  def self.reading_customers_end_tk
    case Snapshot.current_status
    when :reading_customers
      # Prepare Delta Queue for Customers
      snapshot = Snapshot.current

      StUser.order('sat_id').each do |customer|
        full_name = customer.first_name + ' ' + customer.last_name
        qb_customer = nil

	customer_ref = CustomerRef.where("sat_id = #{ customer.sat_id }").first
        customer_ref = CustomerRef.create(sat_id: customer.sat_id) unless customer_ref

	if customer_ref.qb_id
	  qb_customer = QbCustomer.where(
	    "list_id = '#{ customer_ref.qb_id }' AND snapshot_id = #{ snapshot.id }"
	  ).first
	else
	  qb_customer = QbCustomer.where(
	    "name = '#{ full_name }' AND snapshot_id = #{ snapshot.id }"
	  ).first
	end

	if qb_customer
	  customer_ref.update_attributes(
	    edit_sequence: qb_customer.edit_sequence,
	    qb_id:         qb_customer.list_id
	  )

	  unless qb_customer.name == full_name
	    CustomerBit.create(
	      operation:       'upd',
	      first_name:      customer.first_name,
	      last_name:       customer.last_name,
	      customer_ref_id: customer_ref.id
	    )
	  end
	else
	  CustomerBit.create(
	    operation:       'add',
	    first_name:      customer.first_name,
	    last_name:       customer.last_name,
	    customer_ref_id: customer_ref.id
	  )
	end
      end

      Snapshot.move_to(:sending_customers)
    else
      JobProcessor.error_tk("QB reading Customers, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  end

  def self.reading_sales_end_tk
    case Snapshot.current_status
    when :reading_sales
      # Prepare Delta Queue for Sales
      snapshot = Snapshot.current

      StPurchase.order('sat_id').each do |purchase|
        qb_sales_receipt = nil

	sales_receipt_ref = SalesReceiptRef.where("sat_id = #{ purchase.sat_id }").first
        sales_receipt_ref = SalesReceiptRef.create(sat_id: purchase.sat_id) unless sales_receipt_ref

	if sales_receipt_ref.qb_id
	  qb_sales_receipt = QbSalesReceipt.where(
	    "txn_id = '#{ sales_receipt_ref.qb_id }' AND snapshot_id = #{ snapshot.id }"
	  ).first
	end

	if qb_sales_receipt
	  counters = {}
	  qb_lines = {}
          QbSalesReceiptLine.where("qb_sales_receipt_id = #{ qb_sales_receipt.id }").each do |line|
	    key = line.item_ref + line.class_ref + line.quantity + line.amount
	    cnt = 1
	    cnt = counters[key] + 1 if counters[key]
	    counters.merge!(key => cnt)
	    qb_lines.merge!((key + cnt.to_s) => line)
	  end

	  counters = {}
	  st_lines = {}
	  StPurchasePackage.where("sat_id = #{ purchase.sat_id }").each do |pp|
	    key = pp.qb_item_ref + pp.class_ref + pp.quantity + pp.amount
	    cnt = 1
	    cnt = counters[key] + 1 if counters[key]
	    counters.merge!(key => cnt)
	    st_lines.merge!((key + cnt.to_s) => pp)
	  end

	  unless qb_lines.keys == st_lines.keys
	    bit = SalesReceiptBit.create(
	      operation:   'upd',
	      txn_id:      qb_sales_receipt.txn_id,
	      customer_id: purchase.sat_customer_id,
	      ref_number:  purchase.ref_number,
	      txn_date:    purchase.txn_date,
	      sales_receipt_ref_id: sales_receipt_ref.id
	    )

	    st_lines.keys.each do |key|
	      if qb_lines[key].nil?
		SalesReceiptLine.create(
		  txn_line_id: "-1",
		  item_id:     st_line.sat_item_id,
		  quantity:    st_line.quantity,
		  amount:      st_line.amount,
		  class_ref:   st_line.class_ref,
		  sales_receipt_bit_id: bit.id
		)
	      else
		SalesReceiptLine.create(
		  txn_line_id: qb_lines[key].txn_line_id,
		  item_id:     0,
		  sales_receipt_bit_id: bit.id
		)
	      end
	    end

	  end
	else
	  purchase_packages = StPurchasePackage.where("sat_id = #{ purchase.sat_id }")
	  unless purchase_packages.size == 0
	    bit = SalesReceiptBit.create(
	      operation:   'add',
	      customer_id: purchase.sat_customer_id,
	      ref_number:  purchase.ref_number,
	      txn_date:    purchase.txn_date,
	      sales_receipt_ref_id: sales_receipt_ref.id
	    )
	    purchase_packages.each do |pp|
	      SalesReceiptLine.create(
		item_id:   pp.sat_item_id,
		quantity:  pp.quantity,
		amount:    pp.amount,
		class_ref: pp.class_ref,
		sales_receipt_bit_id: bit.id
	      )
	    end
	  end
	end
      end

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

  def self.store_qb_receipt_lines(r, qb_rct)
    if r['sales_receipt_line_ret'] && r['sales_receipt_line_ret'].respond_to?(:to_ary) 
      r['sales_receipt_line_ret'].each do |line| 
	QbSalesReceiptLine.create(
	  txn_line_id: line['txn_line_id'],
	  item_ref:    line['item_ref']['list_id'],
	  class_ref:   line['class_ref']['full_name'],
	  quantity:    line['quantity'],
	  amount:      line['amount'],
	  qb_sales_receipt_id: qb_rct.id
	)
      end
    elsif r['sales_receipt_line_ret']
      QbSalesReceiptLine.create(
	txn_line_id: r['sales_receipt_line_ret']['txn_line_id'],
	item_ref:    r['sales_receipt_line_ret']['item_ref']['list_id'],
	class_ref:   r['sales_receipt_line_ret']['class_ref']['full_name'],
	quantity:    r['sales_receipt_line_ret']['quantity'],
	amount:      r['sales_receipt_line_ret']['amount'],
	qb_sales_receipt_id: qb_rct.id
      )
    end
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
	:include_line_items => 'True'
      }
    }
  end

  def self.build_items_request
    bits = []
    20.times.each do
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
    20.times.each do
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
    20.times.each do
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

    upds = bits.select { |v| v.operation == 'upd' }
    if upds.size > 0
      request.merge!( 
	:sales_receipt_mod_rq => upds.map do |delta|
	  lines = delta.sales_receipt_lines 
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :sales_receipt_mod => {
	      :txn_id => delta.sales_receipt_ref.qb_id,
	      :sales_receipt_line_mod => lines.map do |line|
	        if line.txn_line_id == "-1"
		  item = ItemServiceRef.where("sat_id = #{ line.item_id }").first
		  item_ref = item.qb_id if item
		  {
		    :item_ref    => { list_id: item_ref },
		    :quantity    => line.quantity,
		    :amount      => line.amount,
		    :class_ref   => { full_name: line.class_ref },
		    :txn_line_id => line.txn_line_id
		  }
		else
		  { :txn_line_id => line.txn_line_id }
		end
	      end
	    }
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
