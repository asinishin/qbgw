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
    

    msg_content = nil
    $customers_queue.subscribe do |delivery_info, metadata, payload|
      msg_content = payload
    end
    
    sleep(0.1)

#    _, _, msg_content = $customers_queue.pop
    
    if msg_content
      customer = CustomerBeef.decode(msg_content)
      #if customer.operation == 'add'
      if true
	add_customer(customer)
      else # update operation
        modify_customer(customer)
      end
    end

    req = request
    puts "========== #{ params["Envelope"]["Body"].keys.first}  =========="
    res = QBWC::SoapWrapper.route_request(req)
    render :xml => res, :content_type => 'text/xml'
  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
  end

  def handle_response(job_name)
    Rails.logger.info "Here I am ==> 1"
    QBWC.jobs[job_name].set_response_proc do |r|
      if r['xml_attributes'] && r['xml_attributes']['requestID'] == job_name
	Rails.logger.info "Her I am ==> 2 job: #{ job_name }"
	if r['xml_attributes']['statusCode'] == '0' && r['customer_ret']
	  Rails.logger.info "Her I am ==> 3"
	  yield r['customer_ret']['list_id']
	else
	  Rails.logger.info "Her I am ==> 4"
	  Rails.logger.info "Error: Quickbooks returned an error in response ==>"
	  Rails.logger.info r.inspect
	end
	Rails.logger.info "Her I am ==> 5"
	QBWC.jobs.delete(job_name)
      end
    end
  end

  def gen_job_name
    Time.now.seconds_since_midnight.to_s
  end

  def add_customer(customer)
    customer_ref = CustomerRef.new(sat_id: customer.sat_id)
    customer_ref.save!
    job_name = gen_job_name
    QBWC.add_job(job_name) do
      [
	{
	  :xml_attributes =>  { "onError" => "stopOnError" }, 
	  :customer_add_rq => 
	  [
	    {
	      :xml_attributes => { "requestID" => job_name },
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
    handle_response(job_name) do |list_id|
      customer_ref.qb_id = list_id
      customer_ref.save!
    end
  end

  def modify_customer(customer)
    customer_ref = CustomerRef.where('sat_id = ?', customer.sat_id).first
    if customer_ref
      job_name = gen_job_name
      QBWC.add_job(job_name) do
	[
	  {
	    :xml_attributes =>  { "onError" => "stopOnError" }, 
	    :customer_mod_rq => 
	    [
	      {
		:xml_attributes => { "requestID" => job_name },
		:customer_mod   => {
		  :list_id    => customer_ref.qb_id,
		  :name       => customer.first_name + ' ' + customer.last_name,
		  :first_name => customer.first_name,
		  :last_name  => customer.last_name
		}
	      } 
	    ] 
	  }
	]
      end
      handle_response(job_name)
    end
  end
end
