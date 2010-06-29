require 'rubygems'
require 'scout'

require File.dirname(__FILE__) + '/mysql_query_statistics'

describe MysqlQueryStatistics do
  
  before(:all) do
    
  end
  
  it "should execute the right mysql command" do
    last_run, memory, options=Time.now-3*60, {}, {}
    plugin=MysqlQueryStatistics.new(last_run, memory, options)

    plugin.should_receive(:option).with(:user).and_return('my_user')
    plugin.should_receive(:option).with(:password).and_return('my_password')
    plugin.should_receive(:option).with(:host).and_return('my_host')
    plugin.should_receive(:option).with(:port).and_return('3307')
    plugin.should_receive(:option).with(:socket).and_return(nil)
    plugin.should_receive(:option).with(:sequential_entries).and_return('Com_insert Com_select Com_update Com_delete')
    plugin.should_receive(:option).with(:absolute_entries).and_return('Innodb_buffer_pool_pages_dirty')

    plugin.should_receive(:eval) do |params, result|
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

    plugin = MysqlQueryStatistics.new(last_run, memory, options)
    
    plugin.send(:calculate_counter, 'key', 240, current_run).should == 1
  end


  it "should calculate the right total value" do
    current_run = Time.now
    last_run = current_run - 10
    memory   = { 
        'total' => {:time => last_run, :value => 5 },
      }
    options  = { }

    plugin = MysqlQueryStatistics.new(last_run, memory, options)
    MysqlQueryStatistics::RUN_TIME = current_run

    plugin.should_receive(:eval).and_return(<<-OUT)
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

    plugin = MysqlQueryStatistics.new(last_run, memory, options)
    MysqlQueryStatistics::RUN_TIME = current_run
    
    plugin.should_receive(:eval).and_return(<<-OUT)
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

    plugin = MysqlQueryStatistics.new(last_run, memory, options)
    MysqlQueryStatistics::RUN_TIME = current_run

    plugin.should_receive(:eval).and_return(<<-OUT)
Variable_name	Value
Innodb_buffer_pool_pages_dirty	200
OUT

    plugin.should_receive(:report) do |report_hash|
      report_hash['Innodb_buffer_pool_pages_dirty'].should == 200
    end

    plugin.build_report
  end
  
end
