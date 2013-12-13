require 'item_service_puller'
require 'customer_puller'
require 'sales_receipt_puller'
require 'charge_puller'
require 'qb_iterator'
require 'delta'

class JobProcessor

  FATAL_ERROR = "We are sorry, our server has got a problem. Please contact us and we will fix it shortly."
  QB_ERROR    = "Quickbooks returned an error:\n"

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
      # Clean up queues
      ItemServiceBit.delete_all
      CustomerBit.delete_all
      SalesReceiptLineBit.delete_all
      SalesReceiptBit.delete_all
      ChargeBit.delete_all

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
	# Prepare iterator for reading
	QbIterator.iterator_id = nil
        Snapshot.move_to(:reading_charges)
	JobProcessor.qb_tick_tk
      else
	JobProcessor.wrap_request(request)
      end
    when :reading_charges
      JobProcessor.wrap_request(build_select_charges_request)
    when :sending_charges
      request = JobProcessor.build_charges_request

      if request.size == 0
        JobProcessor.sending_charges_end_tk
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
    JobProcessor.error_tk(FATAL_ERROR)
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
      # If there are no items in QB
      elsif r['xml_attributes']['statusCode'] == "1"
	# Just ignore this error
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
      # If there are no customers in QB
      elsif r['xml_attributes']['statusCode'] == "1"
	# Just ignore this error
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
	      txn_id:        rct['txn_id'],
	      edit_sequence: rct['edit_sequence'],
	      ref_number:    rct['ref_number'],
	      txn_date:      rct['txn_date'],
	      snapshot_id:   curr.id
	    )
	  )
	end
      elsif r['sales_receipt_ret']
	JobProcessor.store_qb_receipt_lines(r['sales_receipt_ret'],
	  QbSalesReceipt.create(
	    txn_id:        r['sales_receipt_ret']['txn_id'],
	    edit_sequence: r['sales_receipt_ret']['edit_sequence'],
	    ref_number:    r['sales_receipt_ret']['ref_number'],
	    txn_date:      r['sales_receipt_ret']['txn_date'],
	    snapshot_id:   curr.id
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
      # If there are no receipts in QB
      elsif r['xml_attributes']['statusCode'] == "1"
	# Just ignore this error
      else
	JobProcessor.error_tk("Unexpected QB Response: #{ r.inspect }")
      end
    when :reading_charges
      QbIterator.remaining_count = r['xml_attributes']['iteratorRemainingCount'].to_i
      curr = Snapshot.current

      if r['charge_ret'] && r['charge_ret'].respond_to?(:to_ary) 
	r['charge_ret'].each do |ch| 
	  QbCharge.create(
	    txn_id:        ch['txn_id'],
	    edit_sequence: ch['edit_sequence'],
	    ref_number:    ch['ref_number'],
	    txn_date:      ch['txn_date'],
	    item_ref:      ch['item_ref']['full_name'],
            quantity:      ch['quantity'],
            amount:        ch['amount'],
	    class_ref:     ch['class_ref']['full_name'],
	    snapshot_id:   curr.id
	  )
	end
      elsif r['charge_ret']
	QbCharge.create(
	  txn_id:        r['charge_ret']['txn_id'],
	  edit_sequence: r['charge_ret']['edit_sequence'],
	  ref_number:    r['charge_ret']['ref_number'],
	  item_ref:      r['charge_ret']['item_ref']['full_name'],
	  txn_date:      r['charge_ret']['txn_date'],
	  quantity:      r['charge_ret']['quantity'],
	  amount:        r['charge_ret']['amount'],
	  class_ref:     r['charge_ret']['class_ref']['full_name'],
	  snapshot_id:   curr.id
	)
      end

      QbIterator.busy = false

      if QbIterator.remaining_count == 0
	JobProcessor.reading_charges_end_tk
      end
    when :sending_charges
      if r['charge_ret'] || r['charge_mod_rs'] || r['charge_add_rs'] || r['txn_del_rs']
        JobProcessor.process_charges_response(r)
      # If there are no receipts in QB
      elsif r['xml_attributes']['statusCode'] == "1"
	# Just ignore this error
      else
	JobProcessor.error_tk("Unexpected QB Response: #{ r.inspect }")
      end
    when :done
      # Nothing to do...
    else
      JobProcessor.error_tk("QB Response, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
    JobProcessor.error_tk(FATAL_ERROR)
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
	    "name = ? AND snapshot_id = #{ snapshot.id }",
	    item.name
	  ).first
	end

	if qb_item
	  item_ref.update_attributes(
	    edit_sequence: qb_item.edit_sequence,
	    qb_id:         qb_item.list_id
	  )

	  unless qb_item.name == item.name && \
	         qb_item.description == item.description.strip && \
		 qb_item.account_ref == item.account_ref
	    ItemServiceBit.create(
	      operation:   'upd',
	      name:        item.name,
	      description: item.description.strip,
	      account_ref: item.account_ref,
	      item_service_ref_id: item_ref.id
	    )
	  end
	else
	  ItemServiceBit.create(
	    operation:   'add',
	    name:        item.name,
	    description: item.description.strip,
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
        full_name = customer.first_name.strip.capitalize  + ' ' + customer.last_name.strip.capitalize
        qb_customer = nil

	customer_ref = CustomerRef.where("sat_id = #{ customer.sat_id }").first
        customer_ref = CustomerRef.create(sat_id: customer.sat_id) unless customer_ref

	if customer_ref.qb_id
	  qb_customer = QbCustomer.where(
	    "list_id = '#{ customer_ref.qb_id }' AND snapshot_id = #{ snapshot.id }"
	  ).first
	else
	  qb_customer = QbCustomer.where(
	    "name = ? AND snapshot_id = #{ snapshot.id }",
	    full_name
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
	      first_name:      customer.first_name.strip.capitalize,
	      last_name:       customer.last_name.strip.capitalize,
	      customer_ref_id: customer_ref.id
	    )
	  end
	else
	  CustomerBit.create(
	    operation:       'add',
	    first_name:      customer.first_name.strip.capitalize,
	    last_name:       customer.last_name.strip.capitalize,
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

      in_ids = StPurchase.select(:sat_id).where(
        'is_cashed AND txn_date between ? AND ?',
	snapshot.date_from,
	snapshot.date_to
      ).order('sat_id').map { |e| e.sat_id }

      out_ids = QbSalesReceipt.select(:txn_id).where(
	'snapshot_id = ?', snapshot.id
      ).order('txn_id').map { |e| e.txn_id }

      out_to_in_hash = {}

      out_to_in = Proc.new do |outs|
        unless outs.size == 0
	  outs.map do |e|
	    unless out_to_in_hash[e]
	      out_to_in_hash.merge!(e => SalesReceiptRef.where('qb_id = ?', e).first.sat_id)
	    end
	    out_to_in_hash[e]
	  end
	else
	  []
	end
      end

      in_to_out_hash = {}

      in_to_out = Proc.new do |ins|
        unless ins.size == 0
	  ins.map do |e|
	    unless in_to_out_hash[e]
	      in_to_out_hash.merge!(
	        e => SalesReceiptRef.where('sat_id = ? AND qb_id IS NOT NULL', e).first.qb_id
	      )
	    end
	    in_to_out_hash[e]
	  end
	else
	  []
	end
      end

      delta = Delta.new(in_ids, out_ids, in_to_out, out_to_in)

      # Update Sales Receipts
      delta.update do |sat_id, txn_id|
	line_out_to_in_hash = {}

	line_out_to_in = Proc.new do |outs|
	  unless outs.size == 0
	    outs.map do |e|
	      unless line_out_to_in_hash[e]
		line_out_to_in_hash.merge!(
		  e => SalesReceiptLineRef.where('txn_line_id = ?', e).first.sat_line_id
		)
	      end
	      line_out_to_in_hash[e]
	    end
	  else
	    []
	  end
	end

	line_in_to_out_hash = {}

	line_in_to_out = Proc.new do |ins|
	  unless ins.size == 0
	    ins.map do |e|
	      unless line_in_to_out_hash[e]
		line_in_to_out_hash.merge!(
		  e => SalesReceiptLineRef.where(
		    'sat_line_id = ? AND txn_line_id IS NOT NULL', e
		  ).first.txn_line_id
		)
	      end
	      line_in_to_out_hash[e]
	    end
	  else
	    []
	  end
	end

        line_in_ids = StPurchasePackage.where(
	  'sat_id = ?', sat_id
	).map { |e| e.sat_line_id }

	qb_sales_receipt = QbSalesReceipt.where(
	  'txn_id = ? AND snapshot_id = ?', txn_id, snapshot.id
	).first
	line_out_ids = qb_sales_receipt.qb_sales_receipt_lines.map { |e| e.txn_line_id }

        line_delta = Delta.new(line_in_ids, line_out_ids, line_in_to_out, line_out_to_in)

        addDirty = false
	line_delta.addition do |sat_line_id|
	  addDirty = true
	end

        delDirty = false
	line_delta.deletion do |txn_line_id|
	  delDirty = true
	end

	bit = nil
	if addDirty || delDirty
	  purchase = StPurchase.where('sat_id = ?', sat_id).first
	  sales_receipt_ref = SalesReceiptRef.where('sat_id = ?', sat_id).first

	  bit = SalesReceiptBit.create(
	    operation:   'upd',
	    customer_id: purchase.sat_customer_id,
	    ref_number:  purchase.ref_number,
	    txn_date:    purchase.txn_date,
	    account_ref: purchase.account_ref,
	    sales_receipt_ref_id: sales_receipt_ref.id
	  )
	end

	if addDirty
	  line_delta.addition do |sat_line_id|
	    line = StPurchasePackage.find_or_create_by_sat_line_id(sat_line_id)
	    ref = SalesReceiptLineRef.find_or_create_by_sat_line_id(sat_line_id)

	    SalesReceiptLineBit.create(
	      operation:   'add',
	      item_id:     line.sat_item_id,
	      quantity:    line.quantity,
	      amount:      line.amount,
	      class_ref:   line.class_ref,
	      sales_receipt_line_ref_id: ref.id,
	      sales_receipt_bit_id: bit.id
	    )
	  end
	end

        if delDirty
          line_delta.deletion do |txn_line_id|
	    SalesReceiptLineBit.create(
	      operation:   'del',
	      item_id:     0,
	      sales_receipt_bit_id: bit.id
	    )
	  end
	end
      end

      # Add new Sales Receipts
      delta.addition do |sat_id|
	purchase = StPurchase.where('sat_id = ?', sat_id).first

	sales_receipt_ref = SalesReceiptRef.find_or_create_by_sat_id(sat_id)

	bit = SalesReceiptBit.create(
	  operation:   'add',
	  customer_id: purchase.sat_customer_id,
	  ref_number:  purchase.ref_number,
	  txn_date:    purchase.txn_date,
	  account_ref: purchase.account_ref,
	  sales_receipt_ref_id: sales_receipt_ref.id
	)

	purchase_packages = StPurchasePackage.where('sat_id = ?', sat_id)
	purchase_packages.each do |pp|
	  ref = SalesReceiptLineRef.find_or_create_by_sat_line_id(pp.sat_line_id)

	  SalesReceiptLineBit.create(
	    operation:   'add',
	    item_id:     pp.sat_item_id,
	    quantity:    pp.quantity,
	    amount:      pp.amount,
	    class_ref:   pp.class_ref,
	    sales_receipt_line_ref_id: ref.id,
	    sales_receipt_bit_id: bit.id
	  )
	end
      end

      # Delete Sales Receipts
      delta.deletion do |txn_id|
	sales_receipt_ref = SalesReceiptRef.where('qb_id = ?', txn_id).first

	SalesReceiptBit.create(
	  operation: 'del',
	  sales_receipt_ref_id: sales_receipt_ref.id
	)
      end

      Snapshot.move_to(:sending_sales)
    else
      JobProcessor.error_tk("QB reading Sales Receipts, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  end

  def self.reading_charges_end_tk
    case Snapshot.current_status
    when :reading_charges
      # Prepare Delta Queue for Charges
      snapshot = Snapshot.current
      
      in_ids = StPurchasePackage.select(:sat_line_id).where(
        %Q{
	  EXISTS (
	    SELECT 'x' FROM st_purchases ps
	    WHERE ps.sat_id = st_purchase_packages.sat_id
	    AND NOT ps.is_cashed
	  ) AND st_purchase_packages.txn_date between ? AND ?
	}.squish, snapshot.date_from, snapshot.date_to
      ).order('sat_line_id').map { |e| e.sat_line_id }

      out_ids = QbCharge.select(:txn_id).where(
        'snapshot_id = ?', snapshot.id
      ).order('txn_id').map { |e| e.txn_id }

      out_to_in_hash = {}

      out_to_in = Proc.new do |outs|
        unless outs.size == 0
	  outs.map do |e|
	    unless out_to_in_hash[e]
	      out_to_in_hash.merge!(e => ChargeRef.where('qb_id = ?', e).first.sat_line_id)
	    end
	    out_to_in_hash[e]
	  end
	else
	  []
	end
      end

      in_to_out_hash = {}

      in_to_out = Proc.new do |ins|
        unless ins.size == 0
	  ins.map do |e|
	    unless in_to_out_hash[e]
	      in_to_out_hash.merge!(
	        e => ChargeRef.where('sat_line_id = ? AND qb_id IS NOT NULL', e).first.qb_id
	      )
	    end
	    in_to_out_hash[e]
	  end
	else
	  []
	end
      end

      delta = Delta.new(in_ids, out_ids, in_to_out, out_to_in)

      # Update charges
      delta.update do |sat_line_id, txn_id|
        st_line = StPurchasePackage.where('sat_line_id = ?', sat_line_id).first
	qb_charge = QbCharge.where(
	  'txn_id = ? AND snapshot_id = ?',
	  txn_id, snapshot.id
	).first
	package = StPackage.where('sat_id = ?', st_line.sat_item_id).first

	# TODO: Will I realy have to update charges?
	unless st_line.quantity.to_d.to_s == qb_charge.quantity.to_d.to_s && \
	       st_line.amount == qb_charge.amount && package.name == qb_charge.item_ref

	  purchase   = StPurchase.where('sat_id = ?', st_line.sat_id).first
	  charge_ref = ChargeRef.where('sat_line_id = ?', sat_line_id).first

	  ChargeBit.create(
	    operation:   'upd',
	    customer_id: purchase.sat_customer_id,
	    ref_number:  purchase.ref_number,
	    txn_date:    st_line.txn_date,
	    item_id:     st_line.sat_item_id,
	    quantity:    st_line.quantity,
	    amount:      st_line.amount,
	    class_ref:   st_line.class_ref,
	    charge_ref_id: charge_ref.id
	  )
	end
      end

      # Create new charges
      delta.addition do |sat_line_id|
        st_line  = StPurchasePackage.where('sat_line_id = ?', sat_line_id).first
	purchase = StPurchase.where('sat_id = ?', st_line.sat_id).first

	charge_ref = ChargeRef.where('sat_line_id = ?', st_line.sat_line_id).first

	unless charge_ref
	  charge_ref = ChargeRef.create(
	    sat_id:      st_line.sat_id,
	    sat_line_id: st_line.sat_line_id
	  )
	end

	ChargeBit.create(
	  operation:   'add',
	  customer_id: purchase.sat_customer_id,
	  ref_number:  purchase.ref_number,
	  txn_date:    st_line.txn_date,
	  item_id:     st_line.sat_item_id,
	  quantity:    st_line.quantity,
	  amount:      st_line.amount,
	  class_ref:   st_line.class_ref,
	  charge_ref_id: charge_ref.id
	)
      end

      # Delete charges
      delta.deletion do |txn_id|
	charge_ref = ChargeRef.where('qb_id = ?', txn_id).first

        # TODO: Remove this, I dont need edit_sequence for deletion
	#qb_charge = QbCharge.where(
	#  'txn_id = ? AND snapshot_id = ?',
	#  txn_id, snapshot.id
	#).first
        #
	#charge_ref.update_attributes(edit_sequence: qb_charge.edit_sequence)

	# Delete a charge
	ChargeBit.create(
	  operation:   'del',
	  charge_ref_id: charge_ref.id
	)
      end

      Snapshot.move_to(:sending_charges)
    else
      JobProcessor.error_tk("QB reading Charges, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  end

  def self.sending_charges_end_tk
    case Snapshot.current_status
    when :sending_charges

      # Email notification
      UserMailer.delay.completion(Snapshot.current.id)

      Snapshot.move_to(:done)
      nil
    else
      JobProcessor.error_tk("QB sending Charges, unexpected status: #{ Snapshot.current_status.to_s }")
    end
  end

  def self.error_tk(err_msg)
    unless err_msg.include?('The request has not been processed')
      # Email notification
      UserMailer.delay.failure(Snapshot.current.id, err_msg)
    end

    Rails.logger.info(err_msg)

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
    QbIterator.request_id = QbIterator.request_id + 1

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

    snapshot = Snapshot.current

    attrs = JobProcessor.prepare_iterator

    {
      :sales_receipt_query_rq => {
	:xml_attributes => attrs,
	:max_returned => 20,
	:txn_date_range_filter => {
	  :from_txn_date => snapshot.date_from.to_s,
	  :to_txn_date   => snapshot.date_to.to_s
	},
	:include_line_items => 'true',
	:owner_id => 0
      }
    }
  end

  def self.build_select_charges_request
    return nil if JobProcessor.iterator_not_ready?

    snapshot = Snapshot.current

    attrs = JobProcessor.prepare_iterator

    {
      :charge_query_rq => {
	:xml_attributes => attrs,
	:max_returned => 20,
	:txn_date_range_filter => {
	  :from_txn_date => snapshot.date_from.to_s,
	  :to_txn_date   => snapshot.date_to.to_s
	}
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
	  lines = delta.sales_receipt_line_bits 
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :sales_receipt_mod => {
	      :txn_id        => delta.sales_receipt_ref.qb_id,
	      :edit_sequence => delta.sales_receipt_ref.edit_sequence,
	      :sales_receipt_line_mod => lines.map do |line|
	        if line.operation == "add"
		  item = ItemServiceRef.where('sat_id = ?', line.item_id).first
		  item_ref = item.qb_id if item
		  {
		    :item_ref    => { list_id: item_ref },
		    :quantity    => line.quantity,
		    :amount      => line.amount,
		    :class_ref   => { full_name: line.class_ref },
		    :txn_line_id => line.sales_receipt_line_ref.txn_line_id
		  }
		else
		  { :txn_line_id => line.sales_receipt_line_ref.txn_line_id }
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
	  lines = delta.sales_receipt_line_bits 
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :sales_receipt_add => {
	      :customer_ref => { list_id: customer_ref },
	      :ref_number => delta.ref_number,
	      :txn_date   => delta.txn_date,
	      :deposit_to_account_ref => { full_name: (delta.account_ref ? delta.account_ref : "Cash Charges") },
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

  def self.build_charges_request
    bits = []
    20.times.each do
      delta = ChargePuller.next_bit
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
	    :txn_del_type   => "Charge",
	    :txn_id => delta.charge_ref.qb_id
	  }
	end 
      )
    end

    # Will I have update? Not sure!
    upds = bits.select { |v| v.operation == 'upd' }
    if upds.size > 0
      request.merge!( 
	:charge_mod_rq => upds.map do |delta|
	  item = ItemServiceRef.where("sat_id = #{ delta.item_id }").first
	  item_ref = item.qb_id if item
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :charge_mod => {
	      :txn_id        => delta.charge_ref.qb_id,
	      :edit_sequence => delta.charge_ref.edit_sequence,
	      :item_ref    => { list_id: item_ref },
	      :quantity    => delta.quantity,
	      :amount      => delta.amount,
	      :class_ref   => { full_name: delta.class_ref }
	    }
	  }
	end 
      )
    end

    news = bits.select { |v| v.operation == 'add' }
    if news.size > 0
      request.merge!( 
	:charge_add_rq => news.map do |delta|
	  customer = CustomerRef.where("sat_id = #{ delta.customer_id }").first
	  customer_ref = customer.qb_id if customer
	  item = ItemServiceRef.where("sat_id = #{ delta.item_id }").first
	  item_ref = item.qb_id if item
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :charge_add => {
	      :customer_ref => { list_id: customer_ref },
	      :ref_number => delta.ref_number,
	      :txn_date   => delta.txn_date,
	      :item_ref  => { list_id: item_ref },
	      :quantity  => delta.quantity,
	      :amount    => delta.amount,
	      :class_ref => { full_name: delta.class_ref }
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
      ItemServicePuller.reset(delta.id) if delta
      JobProcessor.error_tk(QB_ERROR + r.inspect)
    else
      ItemServicePuller.done(delta.id) if delta
    end
    # I dont understand why it is double shooting responses.
    # Still I comment this error for now.
    #if delta.nil?
    #  Rails.logger.info "Error: Quickbooks request is not found ==>"
    #  Rails.logger.info r.inspect
    #end
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
      CustomerPuller.reset(delta.id) if delta
      JobProcessor.error_tk(QB_ERROR + r.inspect)
    else
      CustomerPuller.done(delta.id) if delta
    end
    # I dont understand why it is double shooting responses.
    # Still I comment this error for now.
    #if delta.nil?
    #  Rails.logger.info "Error: Quickbooks request is not found ==>"
    #  Rails.logger.info r.inspect
    #end
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
      line_ret = r['sales_receipt_ret']['sales_receipt_line_ret']
      if line_ret && line_ret.respond_to?(:to_ary)
        line_bits = delta.sales_receipt_line_bits.order('id') 
        line_ret.each_with_index do |line, ix|
	  line_bits[ix].sales_receipt_line_ref.update_attributes(txn_line_id: line['txn_line_id'])
	end
      elsif line_ret 
        line_bit = delta.sales_receipt_line_bits.order('id').first
	line_bit.sales_receipt_line_ref.update_attributes(txn_line_id: line_ret['txn_line_id'])
      end
    end
    if delta && r['xml_attributes']['statusCode'] == '0' && delta.operation == 'del'
      delta.sales_receipt_line_bits.each { |b| b.sales_receipt_line_ref.destroy }
      sales_receipt_ref.destroy
    end
    if r['xml_attributes']['statusCode'] != '0'
      p_no = ""
      if delta
	p_no = " Pruchase: #" + delta.ref_number
	SalesReceiptPuller.reset(delta.id)
      end
      JobProcessor.error_tk(QB_ERROR + r.inspect + p_no)
    else
      SalesReceiptPuller.done(delta.id) if delta
    end
    # I dont understand why it is double shooting responses.
    # Still I comment this error for now.
    #if delta.nil?
    #  Rails.logger.info "Error: Quickbooks request is not found ==>"
    #  Rails.logger.info r.inspect
    #end
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

  def self.process_charges_response_item(r)
    delta = nil
    charge_ref = nil
    if r['xml_attributes']['requestID']
      delta = ChargeBit.where(
	"id = #{ r['xml_attributes']['requestID'] } AND status = 'work'"
      ).first
      charge_ref = delta.charge_ref if delta
    end
    if delta && r['charge_ret'] && r['charge_ret']['edit_sequence']
      edit_sequence = r['charge_ret']['edit_sequence']
      ChargeRef.update_all(
	"edit_sequence = #{ edit_sequence }",
	"id = #{ charge_ref.id } AND (edit_sequence < #{ edit_sequence } OR edit_sequence IS NULL)"
      )
    end
    if delta && r['xml_attributes']['statusCode'] == '0' && delta.operation == 'add'
      charge_ref.update_attribute(:qb_id, r['charge_ret']['txn_id'])
    end
    if delta && r['xml_attributes']['statusCode'] == '0' && delta.operation == 'del'
      charge_ref.destroy
    end
    if r['xml_attributes']['statusCode'] != '0'
      p_no = ""
      if delta
	p_no = " Pruchase: #" + delta.ref_number
	ChargePuller.reset(delta.id)
      end
      JobProcessor.error_tk(QB_ERROR + r.inspect + p_no)
    else
      ChargePuller.done(delta.id) if delta
    end
    # I dont understand why it is double shooting responses.
    # Still I comment this error for now.
    #if delta.nil?
    #  Rails.logger.info "Error: Quickbooks request is not found ==>"
    #  Rails.logger.info r.inspect
    #end
  end

  def self.process_charges_response(r)
    # TxnDelRs array case 
    if r['txn_del_rs'].respond_to?(:to_ary)
      r['txn_del_rs'].each{ |item| JobProcessor.process_charges_response_item item }
    # Or one item
    elsif r['txn_del_rs']
      JobProcessor.process_charges_response_item r['txn_del_rs']
    end

    # SalesReceiptAddRs array case
    if r['charge_add_rs'].respond_to?(:to_ary)
      r['charge_add_rs'].each{ |item| JobProcessor.process_charges_response_item item }
    # Or one item
    elsif r['charge_add_rs']
      JobProcessor.process_charges_response_item r['charge_add_rs']
    end

    # Single request case
    if r['charge_ret'] && r['xml_attributes']['requestID']
      JobProcessor.process_charges_response_item r
    end
  end

end
