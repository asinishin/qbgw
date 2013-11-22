require 'customer_puller'
require 'quickbooks'     # TODO check if anything broken

class QbwcController < ApplicationController
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

    build_qbxml_request

    req = request
    puts "========== #{ params["Envelope"]["Body"].keys.first}  =========="
    res = QBWC::SoapWrapper.route_request(req)
    render :xml => res, :content_type => 'text/xml'

  rescue Exception => e
    Rails.logger.info "Error ==>"
    Rails.logger.info(e.class.name + ':' + e.to_s)
    Rails.logger.info e.backtrace.join("\n")
  end

  def set_response_handler(job)
    Rails.logger.info "Here I am ==> 1"
    job.set_response_proc do |r|
      delta = CustomerBit.where(
	"id = #{ r['xml_attributes']['requestID'] } AND status = 'work'"
      ).first
      if r['xml_attributes']['statusCode'] != '0'
	Rails.logger.info "Error: Quickbooks returned an error ==>"
	Rails.logger.info r.inspect
	CustomerPuller.reset(delta.id) if delta
      elsif delta
	if delta.operation == 'add'
	  customer_ref = delta.customer_ref
	  customer_ref.qb_id         = r['customer_ret']['list_id']
	  customer_ref.edit_sequence = r['customer_ret']['edit_sequence']
	  customer_ref.save!
	end
	CustomerPuller.done(delta.id)
      else
	Rails.logger.info "Error: Quickbooks request is not found ==>"
	Rails.logger.info r.inspect
      end
    end
  end

  def build_qbxml_request
    mods = CustomerPuller.modifications
    news = CustomerPuller.news

    return if mods.size == 0 && news.size == 0

    request_hash = { :xml_attributes =>  { "onError" => "stopOnError" } }

    if mods.size > 0
      request_hash.merge!(
	:customer_mod_rq => mods.map do |delta|
	  {
	    :xml_attributes => { "requestID" => delta.id },
	    :customer_mod   => {
	      :list_id       => delta.customer_ref.qb_id,
	      :edit_sequence => delta.customer_ref.edit_sequence + delta.input_order,
	      :name          => delta.first_name + ' ' + delta.last_name,
	      :first_name    => delta.first_name,
	      :last_name     => delta.last_name
	    }
	  }
	end
      )
    end

    if news.size > 0
      request_hash.merge!(
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

    set_response_handler(QBWC.add_job(:import_customers) { [request_hash] })

  end

end
