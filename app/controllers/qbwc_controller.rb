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

  def set_response_handler(job_name)
    Rails.logger.info "Here I am ==> 1 #{job_name}"
    QBWC.jobs[job_name].set_response_proc do |r|
      Rails.logger.info "Here I am ==> 2 #{job_name}"

      # CustomerModRs array case
      if r['customer_mod_rs'].respond_to?(:to_ary)
        r['customer_mod_rs'].each{ |item| process_response_item item }
      end

      # CustomerAddRs array case
      if r['customer_add_rs'].respond_to?(:to_ary)
        r['customer_add_rs'].each{ |item| process_response_item item }
      end

      # Single request case
      if r['xml_attributes']['requestID']
        process_response_item r
      end

      QBWC.jobs.delete(job_name)
    end
  end

  def process_response_item(r)
    delta = nil
    customer_ref = nil
    if r['xml_attributes']['requestID']
      delta = CustomerBit.where(
	"id = #{ r['xml_attributes']['requestID'] } AND status = 'work'"
      ).first
      customer_ref = delta.customer_ref
    end
    if delta && r['customer_ret']['edit_sequence']
      edit_sequence = r['customer_ret']['edit_sequence'])
      CustomerRef.update_all(
	"edit_sequence = #{ edit_sequence }",
	"id = #{ customer_ref.id } AND edit_sequence < #{ edit_sequence }"
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
	      :edit_sequence => delta.customer_ref.edit_sequence + delta.input_order - 1,
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
    
    job_name = gen_job_name
    QBWC.add_job(job_name) { [request_hash] }
    set_response_handler(job_name)

  end

  def gen_job_name
    $q_tick += 1
    Time.now.seconds_since_midnight.to_s + '.' + $q_tick.to_s
  end

end
