require File.dirname(__FILE__) + '/../spec/spec_helper'
require File.dirname(__FILE__) + '/log_watcher_advanced'

describe LogWatcherAdvanced do
  
  it "should execute for the first time with no file scan" do
    last_run, memory, options = Time.now-3*60, {}, {}
    plugin = LogWatcherAdvanced.new(last_run, memory, options)

    plugin.should_receive(:option).with(:log_path).and_return('/var/log/my.log')
    plugin.should_receive(:option).with(:service_name).and_return('MyService')
    plugin.should_receive(:option).with(:value_pipe).and_return('value_pipe')
    plugin.should_receive(:option).with(:error_pipe).and_return('error_pipe')

    plugin.should_receive(:eval).once.with(%Q[`wc -c /var/log/my.log`]).and_return("0 /var/log/my.log")

    plugin.build_report

    @report_hash = plugin.data_for_server[:reports].inject({}){|r,d|r.merge!(d)}
    
    @report_hash[:value].should == 0
  end

  it "should execute the second time with the right value and error command" do
    last_run, memory, options = Time.now-3*60, {}, {}
    
    memory[:last_run] = 0
    
    plugin = LogWatcherAdvanced.new(last_run, memory, options)

    plugin.should_receive(:option).with(:log_path).and_return('/var/log/my.log')
    plugin.should_receive(:option).with(:service_name).and_return('MyService')
    plugin.should_receive(:option).with(:value_pipe).and_return('value_pipe')
    plugin.should_receive(:option).with(:error_pipe).and_return('error_pipe')

    eval_run_count = 0
    plugin.should_receive(:eval).exactly(3).times do |params|
      case eval_run_count+=1
        when 1
          params.should == %Q[`wc -c /var/log/my.log`]
          "10 /var/log/my.log"
        when 2
          params.should == %Q[`tail -c +0 /var/log/my.log | head -c 10 | value_pipe`]
          "value_result"
        when 3
          params.should == %Q[`tail -c +0 /var/log/my.log | head -c 10 | error_pipe`]
          "error_result"
      end
      
    end

    plugin.should_receive(:build_alert).with('error_result').and_return('build_alert_result')
    plugin.should_receive(:alert).with('build_alert_result', "")

    plugin.build_report
    
    @report_hash = plugin.data_for_server[:reports].inject({}){|r,d|r.merge!(d)}
    
    @report_hash[:value].should == "value_result"
  end

end