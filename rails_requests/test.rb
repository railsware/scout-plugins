require File.dirname(__FILE__)+"/../test_helper"
require File.dirname(__FILE__)+"/rails_requests"

class RailsRequestsTest < Test::Unit::TestCase

  def setup
    @options=parse_defaults("rails_requests")
    @log = File.dirname(__FILE__)+"/log/production_rails_2_3.log"
    @rails3_log = File.dirname(__FILE__)+"/log/production_rails_3b3.log"
  end

  def test_run_rails_2_3
    plugin=RailsRequests.new(nil,{:last_request_time=>Time.parse("2010-04-26 00:00:00")},@options.merge(:log => @log))
    res=plugin.run
    assert_equal 0.0, res[:reports].first[:slow_requests_percentage]
    assert_equal "0.36", res[:reports].first[:average_request_length]
    assert_equal "0.04", res[:reports].first[:average_db_time]
    assert_equal "0.30", res[:reports].first[:average_view_time]
    assert_equal 1, res[:summaries].size
  end

  def test_run_with_slow_request_rails_2_3
    plugin=RailsRequests.new(nil,{:last_request_time=>Time.parse("2010-04-26 00:00:00")},@options.merge(:log => @log, :max_request_length=>2))
    res=plugin.run
    assert_equal 10, res[:reports].first[:slow_requests_percentage]
    assert_equal 1, res[:alerts].size
    assert_equal "Maximum Time(2 sec) exceeded on 1 request",res[:alerts].first[:subject]
    assert_match %r(http://hotspotr.com/wifi/map/660-vancouver-canada), res[:alerts].first[:body] 
  end

  def test_ignored_slow_request_rails_2_3
    plugin=RailsRequests.new(nil,{:last_request_time=>Time.parse("2010-04-26 00:00:00")},@options.merge(:log => @log, :max_request_length=>2, :ignored_actions=>'map'))
    res=plugin.run
    assert_equal 0, res[:reports].first[:slow_requests_percentage]
    assert_equal 0, res[:alerts].size
  end

  def test_run_with_two_slow_requests_rails_2_3
    plugin=RailsRequests.new(nil,{:last_request_time=>Time.parse("2010-04-26 00:00:00")},@options.merge(:log => @log, :max_request_length=>1))
    res=plugin.run
    assert_equal 20, res[:reports].first[:slow_requests_percentage]
    assert_equal 1, res[:alerts].size
    assert_equal "Maximum Time(1 sec) exceeded on 2 requests", res[:alerts].first[:subject]
    assert_equal "http://hotspotr.com/wifi/map/660-vancouver-canada\nCompleted in 2100ms (View: 100, DB: 2000) | 200 OK \n\nhttp://hotspotr.com/wifi\nCompleted in 1001ms (View: 24, DB: 900) | 200 OK \n\n",
                  res[:alerts].first[:body]
  end

  def test_run_rails_3
    plugin=RailsRequests.new(nil,{:last_request_time=>Time.parse("2010-04-26 00:00:00")},@options.merge(:log => @rails3_log, :rails_version => '3'))
    res=plugin.run
    assert_equal "0.39", res[:reports].first[:average_request_length]
    assert_equal "0.00", res[:reports].first[:average_db_time]   # NOTE: the Rails3 Parser doesn't extract these values 4/30/2010
    assert_equal "0.00", res[:reports].first[:average_view_time] # NOTE: the Rails3 Parser doesn't extract these values 4/30/2010
  end

  def test_run_with_slow_request_rails_3
    plugin=RailsRequests.new(nil,{:last_request_time=>Time.parse("2010-04-26 00:00:00")},@options.merge(:log => @rails3_log, :max_request_length=>2, :rails_version => '3'))
    res=plugin.run
    assert_equal 10, res[:reports].first[:slow_requests_percentage]
    assert_equal 1, res[:alerts].size
    assert_equal "Maximum Time(2 sec) exceeded on 1 request",res[:alerts].first[:subject]
    assert_equal "/home\nCompleted 200 OK in 2100ms (Views: 1900ms | ActiveRecord: 100ms)\n\n\n", res[:alerts].first[:body]
  end

  def test_ignored_slow_request_rails_3
    plugin=RailsRequests.new(nil,{:last_request_time=>Time.parse("2010-04-26 00:00:00")},@options.merge(:log => @rails3_log, :max_request_length=>2, :ignored_actions=>'home', :rails_version => '3'))
    res=plugin.run
    assert_equal 0, res[:reports].first[:slow_requests_percentage]
    assert_equal 0, res[:alerts].size
  end

  def test_wrong_log_path
    plugin=RailsRequests.new(nil,{:last_request_time=>Time.parse("2010-04-26 00:00:00")},@options.merge(:log => "BOGUS"))
    res=plugin.run
    assert_equal 1, res[:errors].size
    assert_match /Unable to find the Rails log file/, res[:errors].first[:subject]
  end

  def test_empty_log_file
    plugin=RailsRequests.new(nil,{:last_request_time=>Time.parse("2010-04-26 00:00:00")},
                             @options.merge(:log =>  File.dirname(__FILE__)+"/log/empty.log"))
    res=plugin.run
    assert_equal 0, res[:errors].size, res.to_yaml
    assert_equal 0, res[:alerts].size
  end



end