class TestsController < ApplicationController

  def index
    QBWC.add_job(:import_customers) do
#      [
#        :customer_query_rq  =>
#        {
#          :xml_attributes => { "requestID" =>"1", 'iterator'  => "Start" },
#          :max_returned => 5
#        }
#      ]
      [
	{
	  :xml_attributes =>  { "onError" => "stopOnError"}, 
	  :customer_add_rq => 
	  [
	    {
	      :xml_attributes => {"requestID" => "1"},  ##Optional
	      :customer_add   => { :name => "GermanGR" }
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
    render text: 'Ok'
  end

end
