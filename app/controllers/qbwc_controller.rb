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

    _, _, msg_content = $rabbitmq_queue.pop

    if msg_content
      QBWC.add_job(:import_customers) do
	[
	  {
	    :xml_attributes =>  { "onError" => "stopOnError"}, 
	    :customer_add_rq => 
	    [
	      {
		:xml_attributes => {"requestID" => "1"},  ##Optional
		:customer_add   => { :name => msg_content.inspect }
	      } 
	    ] 
	  }
	]
      end
      QBWC.jobs[:import_customers].set_response_proc do |r|
	puts "Here we are ===>"
	p r
	QBWC.jobs.delete(:import_customers)
      end
    end

    req = request
    puts "========== #{ params["Envelope"]["Body"].keys.first}  =========="
    res = QBWC::SoapWrapper.route_request(req)
    render :xml => res, :content_type => 'text/xml'
  end

end
