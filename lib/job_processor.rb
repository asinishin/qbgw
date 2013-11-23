require 'customer_puller'

class JobProcessor

  def self.start
    # Processing modifications
    QBWC.add_job(:customer_upd) do
      delta = CustomerPuller.modification_bit

      if delta
	{ :xml_attributes =>  { "onError" => "stopOnError" }, 
	  :customer_mod_rq => [
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
	  ]
	}
      end
    end

    QBWC.jobs[:customer_upd].set_response_proc do |r|
      Rails.logger.info "Here I am ==> Customer Update Callback"
      Rails.logger.info r.inspect

      JobProcessor::process_response_item r

    end

    # Processing new customers
    QBWC.add_job(:customer_add) do
      delta = CustomerPuller.creation_bit

      if delta
	{ :xml_attributes =>  { "onError" => "stopOnError" }, 
	  :customer_add_rq => [
	    {
	      :xml_attributes => { "requestID" => delta.id },
	      :customer_add   => {
		:name       => delta.first_name + ' ' + delta.last_name,
		:first_name => delta.first_name,
		:last_name  => delta.last_name
	      }
	    }
	  ]
	}
      end
    end

    QBWC.jobs[:customer_add].set_response_proc do |r|
      Rails.logger.info "Here I am ==> Customer Add Callback"
      Rails.logger.info r.inspect

      JobProcessor::process_response_item r

    end
  end

  def self.process_response_item(r)
    delta = nil
    customer_ref = nil
    if r['xml_attributes']['requestID']
      delta = CustomerBit.where(
	"id = #{ r['xml_attributes']['requestID'] } AND status = 'work'"
      ).first
      customer_ref = delta.customer_ref if delta
    end
    if delta && r['customer_ret']['edit_sequence']
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
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

end
