require 'sales_receipt_puller'

class SalesReceiptJobProcessor

  def self.start
    # Processing removal
    QBWC.add_job(:sales_receipt_del) do
      request = nil
      dels = []
      10.times.each do
	delta = SalesReceiptPuller.removal_bit
	break if delta.nil?

	dels << delta
      end

      if false # dels.size > 0
	request = [{ 
	  :xml_attributes =>  { "onError" => "stopOnError" }, 
	  :txn_del_rq => dels.map do |delta|
	    {
	      :xml_attributes => { "requestID" => delta.id },
	      :txn_del => {
		:list_id => delta.sales_receipt_ref.qb_id
	      }
	    }
	  end 
	}]
      end
      request
    end

    QBWC.jobs[:sales_receipt_del].set_response_proc do |r|
      Rails.logger.info "Here I am ==> Sales Receipt Removal Callback"
      Rails.logger.info r.inspect

      SalesReceiptJobProcessor::process_response r

    end

    # Processing new sales receipt 
    QBWC.add_job(:sales_receipt_add) do
      request = nil
      news = []
      10.times.each do
	delta = SalesReceiptPuller.creation_bit
	break if delta.nil?
        
	news << delta
      end

      if news.size > 0
	request = [{ 
	  :xml_attributes => { "onError" => "stopOnError" },
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
	}]
      end
      request
    end

    QBWC.jobs[:sales_receipt_add].set_response_proc do |r|
      Rails.logger.info "Here I am ==> Sales Receipt Add Callback"
      Rails.logger.info r.inspect

      SalesReceptJobProcessor::process_response r

    end
  end

  def self.process_response_item(r)
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
      sales_receipt_ref.update_attribute(:qb_id, r['sales_receipt_ret']['list_id'])
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
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

  def self.process_response(r)
    r = r['qbxml_msgs_rs'] if r['qbxml_msgs_rs']

    # ItemServiceModRs array case # TODO REMOVAL should be here
#    if r['item_service_mod_rs'].respond_to?(:to_ary)
#      r['item_service_mod_rs'].each{ |item| ItemServiceJobProcessor::process_response_item item }
#    # Or one item
#    elsif r['item_service_mod_rs']
#      ItemServiceJobProcessor::process_response_item r['item_service_mod_rs']
#    end

    # SalesReceiptAddRs array case
    if r['sales_receipt_add_rs'].respond_to?(:to_ary)
      r['sales_receipt_add_rs'].each{ |item| SalesReceiptJobProcessor::process_response_item item }
    # Or one item
    elsif r['sales_receipt_add_rs']
      SalesReceiptJobProcessor::process_response_item r['sales_receipt_add_rs']
    end

    # Single request case
    if r['xml_attributes']['requestID']
      SalesReceiptJobProcessor::process_response_item r
    end
  end

end
