require 'customer_beef'

class QbwcController < ApplicationController
  require "quickbooks"
  protect_from_forgery :except => :api 
  def qwc
    qwc = <<-QWC
    <QBWCXML>
    <AppName>#{Rails.application.class.parent_name} #{Rails.env}</AppName>
    <AppID></AppID>
    <AppURL>#{quickbooks_url(:protocol => 'https://', :action => 'api')}</AppURL>
    <AppDescription>I like to describe my awesome app</AppDescription>
    <AppSupport>#{QBWC.support_site_url}</AppSupport>
    <UserName>#{QBWC.username}</UserName>
    <OwnerID>#{QBWC.owner_id}</OwnerID>
    <FileID>{90A44FB5-33D9-4815-AC85-BC87A7E7D1EB}</FileID>
    <QBType>QBFS</QBType>
    <Style>Document</Style>
    <Scheduler>
      <RunEveryNMinutes>5</RunEveryNMinutes>
    </Scheduler>
    </QBWCXML>
    QWC
    send_data qwc, :filename => 'name_me.qwc'
  end

  def api
    # respond successfully to a GET which some versions of the Web Connector send to verify the url

    if request.get?
      render :nothing => true
      return
    end

    _, _, msg_content = $customers_queue.pop
    
    if msg_content
      customer = CustomerBeef.decode(msg_content)
      if customer.operation == 'add'
	customer_ref = CustomerRef.new(sat_id: customer.sat_id)
	customer_ref.save!
	QBWC.add_job(:import_customers) do
	  [
	    {
	      :xml_attributes =>  { "onError" => "stopOnError" }, 
	      :customer_add_rq => 
	      [
		{
		  :xml_attributes => { "requestID" => customer.sat_id.to_s },  ##Optional
		  :customer_add   => {
		    :name       => customer.first_name + ' ' + customer.last_name,
		    :first_name => customer.first_name,
		    :last_name  => customer.last_name
		  }
		} 
	      ] 
	    }
	  ]
	end
	QBWC.jobs[:import_customers].set_response_proc do |r|
	  if r['xml_attributes'] && r['xml_attributes']['statusCode'] == '0' && r['xml_attributes']['requestID'] == customer.sat_id.to_s && r['customer_ret']
	    customer_ref.qb_id = r['customer_ret']['list_id']
	    customer_ref.save!
	  else
	    Rails.logger.info "Error: Quickbooks returned an error in response ==>"
	    Rails.logger.info r.inspect
	  end
	  QBWC.jobs.delete(:import_customers)
	end
      end
    end

    req = request
    puts "========== #{ params["Envelope"]["Body"].keys.first}  =========="
    res = QBWC::SoapWrapper.route_request(req)
    render :xml => res, :content_type => 'text/xml'
  end

end
