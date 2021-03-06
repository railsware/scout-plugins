require File.dirname(__FILE__) + '/../spec/spec_helper'
require File.dirname(__FILE__) + '/mysql_statistics'

describe MysqlStatistics do
  
  it "should execute the right mysql command" do
    last_run, memory, options=Time.now-3*60, {}, {}
    plugin=MysqlStatistics.new(last_run, memory, options)

    plugin.should_receive(:option).with(:user).and_return('my_user')
    plugin.should_receive(:option).with(:password).and_return('my_password')
    plugin.should_receive(:option).with(:host).and_return('my_host')
    plugin.should_receive(:option).with(:port).and_return('3307')
    plugin.should_receive(:option).with(:socket).and_return(nil)
    plugin.should_receive(:option).with(:sequential_entries).and_return('Com_insert Com_select Com_update Com_delete')
    plugin.should_receive(:option).with(:absolute_entries).and_return('Innodb_buffer_pool_pages_dirty')

    Open3.should_receive(:popen3) do |params, result|
      cmd = params.first
      cmd.should include('--user="my_user"')
      cmd.should include('--password="my_password"')
      cmd.should include('--port="3307"')
      cmd.should include('--host="my_host"')
      cmd.should include('--socket=""')
<<-OUT
Variable_name	Value
Com_insert	240
OUT
    end

    plugin.build_report
  end

  it "should correctly calculate calculate_counter" do
    current_run = Time.now
    last_run = current_run - 3*60
    memory   = { 'key' => {:time => last_run, :value => 60 }  }
    options  = {}

    plugin = MysqlStatistics.new(last_run, memory, options)
    
    plugin.send(:calculate_counter, 'key', 240, current_run).should == 1
  end


  it "should calculate the right total value" do
    current_run = Time.now
    last_run = current_run - 10
    memory   = { 
        'total' => {:time => last_run, :value => 5 },
      }
    options  = { }

    plugin = MysqlStatistics.new(last_run, memory, options)
    plugin.run_time = current_run

    Open3.should_receive(:popen3).and_return(<<-OUT)
Variable_name	Value
Com_a	5
Com_b	5
Com_c	5
OUT

    plugin.should_receive(:report) do |report_hash|
      report_hash['total'].should == 1
    end

    plugin.build_report
  end

  it "should calculate the right sequential value" do
    current_run = Time.now
    last_run = current_run - 3*60
    memory   = { 'Com_insert' => {:time => last_run, :value => 60 }  }
    options  = { :sequential_entries => 'Com_insert'}

    plugin = MysqlStatistics.new(last_run, memory, options)
    plugin.run_time = current_run
    
    Open3.should_receive(:popen3).and_return(<<-OUT)
Variable_name	Value
Com_insert	240
OUT
    
    plugin.should_receive(:report) do |report_hash|
      report_hash['Com_insert'].should == 1
    end
    
    plugin.build_report
  end

  it "should calculate the right absolute value" do
    current_run = Time.now
    last_run = current_run - 3*60
    memory   = { 'Innodb_buffer_pool_pages_dirty' => {:time => last_run, :value => 100 }  }
    options  = { :absolute_entries => 'Innodb_buffer_pool_pages_dirty'}

    plugin = MysqlStatistics.new(last_run, memory, options)
    plugin.run_time = current_run

    Open3.should_receive(:popen3).and_return(<<-OUT)
Variable_name	Value
Innodb_buffer_pool_pages_dirty	200
OUT

    plugin.build_report

    @report_hash = plugin.data_for_server[:reports].inject({}){|r,d|r.merge!(d)}
    @report_hash['Innodb_buffer_pool_pages_dirty'].should == 200
  end
  
  it "should generate an error alert with specific message" do
    current_run = Time.now
    last_run = current_run - 3*60
    memory, options = {}, {}

    plugin = MysqlStatistics.new(last_run, memory, options)
    plugin.run_time = current_run

    Open3.should_receive(:popen3).and_return([nil, "cannot connect to mysql"])

    plugin.build_report

    errors = plugin.data_for_server[:errors]
    errors.length.should == 1
    errors.first[:subject].should == "errors while getting mysql stats"
    errors.first[:body].should == "cannot connect to mysql"      
  end

  it "should generate an error alert with empty output" do
    current_run = Time.now
    last_run = current_run - 3*60
    memory, options = {}, {}

    plugin = MysqlStatistics.new(last_run, memory, options)
    plugin.run_time = current_run

    Open3.should_receive(:popen3).and_return(["", ""])

    plugin.build_report

    errors = plugin.data_for_server[:errors]
    errors.length.should == 1
    errors.first[:subject].should == "errors while getting mysql stats"
    errors.first[:body].should == "no result was retreived by the command : \nmysql --execute=\"SHOW /*!50002 GLOBAL */ STATUS\" --user=\"root\" --host=\"\" --port=\"\" --password=\"\" --socket=\"\" | tail -n +2"
  end


end
