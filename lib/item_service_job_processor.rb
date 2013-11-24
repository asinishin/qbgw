require 'item_service_puller'

class ItemServiceJobProcessor

  def self.start
    # Processing modifications
    QBWC.add_job(:item_service_upd) do
      request = nil
      mods = []
      10.times.each do
	delta = ItemServicePuller.modification_bit
	break if delta.nil?

	mods << delta
      end

      if mods.size > 0
	request = [{ 
	  :xml_attributes =>  { "onError" => "stopOnError" }, 
	  :item_service_mod_rq => mods.map do |delta|
	    {
	      :xml_attributes => { "requestID" => delta.id },
	      :item_service_mod   => {
		:list_id       => delta.item_service_ref.qb_id,
		:edit_sequence => delta.item_service_ref.edit_sequence,
		:name          => delta.name,
		:sales_or_purchase_mod => {
		  :desc => delta.description,
		  :price => '0.0',
                  :account_ref => { full_name: delta.account_ref }
		}
	      }
	    }
	  end 
	}]
      end
      request
    end

    QBWC.jobs[:item_service_upd].set_response_proc do |r|
      Rails.logger.info "Here I am ==> Item Service Update Callback"
      Rails.logger.info r.inspect

      ItemServiceJobProcessor::process_response r

    end

    # Processing new item services
    QBWC.add_job(:item_service_add) do
      request = nil
      news = []
      10.times.each do
	delta = ItemServicePuller.creation_bit
	break if delta.nil?
        
	news << delta
      end

      if news.size > 0
	request = [{ 
	  :xml_attributes =>  { "onError" => "stopOnError" },
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
	}]
      end
      request
    end

    QBWC.jobs[:item_service_add].set_response_proc do |r|
      Rails.logger.info "Here I am ==> Item Service Add Callback"
      Rails.logger.info r.inspect

      ItemServiceJobProcessor::process_response r

    end
  end

  def self.process_response_item(r)
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
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

  def self.process_response(r)
    r = r['qbxml_msgs_rs'] if r['qbxml_msgs_rs']

    # ItemServiceModRs array case
    if r['item_service_mod_rs'].respond_to?(:to_ary)
      r['item_service_mod_rs'].each{ |item| ItemServiceJobProcessor::process_response_item item }
    # Or one item
    elsif r['item_service_mod_rs']
      ItemServiceJobProcessor::process_response_item r['item_service_mod_rs']
    end

    # ItemServiceAddRs array case
    if r['item_service_add_rs'].respond_to?(:to_ary)
      r['item_service_add_rs'].each{ |item| ItemServiceJobProcessor::process_response_item item }
    # Or one item
    elsif r['item_service_add_rs']
      ItemServiceJobProcessor::process_response_item r['item_service_add_rs']
    end

    # Single request case
    if r['xml_attributes']['requestID']
      ItemServiceJobProcessor::process_response_item r
    end
  end

end
