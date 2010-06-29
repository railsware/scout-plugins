require File.dirname(__FILE__)+"/../test_helper"
require File.dirname(__FILE__)+"/postgresql_monitoring"
require 'pg'

class PostgresqlMonitoringTest < Test::Unit::TestCase

  def setup
    @options=parse_defaults("postgresql_monitoring")
  end
  
  # Simuates 2 runs of the plugin to check on counter behavior and reported data.
  def test_two_runs
    @plugin=PostgresqlMonitoring.new(nil,{},@options)
    # TODO - FIX WARNING
    PGconn.any_instance.stubs(:initialize).returns(PGconn.new)
    
    row_stats=PGresult.new
    # row data
    row_stats.stubs(:[]).with(0).returns(FIXTURES[:rows_initial])
    # this is returning 
    PGconn.any_instance.stubs(:exec).with('SELECT sum(idx_tup_fetch) AS "rows_select_idx", 
                                 sum(seq_tup_read) AS "rows_select_scan", 
                                 sum(n_tup_ins) AS "rows_insert", 
                                 sum(n_tup_upd) AS "rows_update",
                                 sum(n_tup_del) AS "rows_delete",
                                 (sum(idx_tup_fetch) + sum(seq_tup_read) + sum(n_tup_ins) + sum(n_tup_upd) + sum(n_tup_del)) AS "rows_total"
                          FROM pg_stat_all_tables;').returns(row_stats)
    # cache data
    cache_stats=PGresult.new
    cache_stats.stubs(:[]).with(0).returns(FIXTURES[:cache_initial])
    PGconn.any_instance.stubs(:exec).with('SELECT sum(numbackends) AS "numbackends", 
                                 sum(xact_commit) AS "xact_commit", 
                                 sum(xact_rollback) AS "xact_rollback", 
                                 sum(xact_commit+xact_rollback) AS "xact_total", 
                                 sum(blks_read) AS "blks_read", 
                                 sum(blks_hit) AS "blks_hit"
                          FROM pg_stat_database;').returns(cache_stats)
    
    # 10 minutes in the past
    time = Time.now
    Timecop.travel(time-60*10) do 
      res= @plugin.run()
    
      assert res[:errors].empty?
      assert res[:alerts].empty?
      
      # ensure data is stored from counter  
      FIXTURES[:rows_initial].each do |k,v|
        assert_equal v.to_i, res[:memory]["_counter_#{k}"][:value], "Memory for #{k} incorrect"
      end
    
      FIXTURES[:cache_initial].reject { |k,v| PostgresqlMonitoring::NON_COUNTER_ENTRIES.include?(k) }.each do |k,v|
        assert_equal v.to_i, res[:memory]["_counter_#{k}"][:value], "Memory for #{k} incorrect"
      end 
      
      # verify cache hit rate
      reports = res[:reports]
      assert_equal (70/80.to_f*100).to_i, reports.first['blks_cache_pc']
      
      first_run_memory = res[:memory]
            
      # now - 10 minutes later
      Timecop.travel(time) do 
        # row data
        row_stats.stubs(:[]).with(0).returns(FIXTURES[:rows_second_run])
        # this is returning 
        PGconn.any_instance.stubs(:exec).with('SELECT sum(idx_tup_fetch) AS "rows_select_idx", 
                                     sum(seq_tup_read) AS "rows_select_scan", 
                                     sum(n_tup_ins) AS "rows_insert", 
                                     sum(n_tup_upd) AS "rows_update",
                                     sum(n_tup_del) AS "rows_delete",
                                     (sum(idx_tup_fetch) + sum(seq_tup_read) + sum(n_tup_ins) + sum(n_tup_upd) + sum(n_tup_del)) AS "rows_total"
                              FROM pg_stat_all_tables;').returns(row_stats)
        # cache data
        cache_stats.stubs(:[]).with(0).returns(FIXTURES[:cache_second_run])
        PGconn.any_instance.stubs(:exec).with('SELECT sum(numbackends) AS "numbackends", 
                                     sum(xact_commit) AS "xact_commit", 
                                     sum(xact_rollback) AS "xact_rollback", 
                                     sum(xact_commit+xact_rollback) AS "xact_total", 
                                     sum(blks_read) AS "blks_read", 
                                     sum(blks_hit) AS "blks_hit"
                              FROM pg_stat_database;').returns(cache_stats)
        
        @plugin=PostgresqlMonitoring.new(time-60*10,first_run_memory,@options)
        res= @plugin.run()

        assert res[:errors].empty?
        assert res[:alerts].empty?
        
        reports = res[:reports]        
        
        # check the rate for rows total
        assert_in_delta 100/(10*60).to_f, reports.first['rows_total'], 0.001

        FIXTURES[:rows_second_run].each do |k,v|
          assert_equal v.to_i, res[:memory]["_counter_#{k}"][:value], "Memory for #{k} incorrect"
        end

        FIXTURES[:cache_second_run].reject { |k,v| PostgresqlMonitoring::NON_COUNTER_ENTRIES.include?(k) }.each do |k,v|
          assert_equal v.to_i, res[:memory]["_counter_#{k}"][:value], "Memory for #{k} incorrect"
        end
        
      end # 2nd run
    
    end # Timecop
    
  end
  
  def test_second_run
    
  end
  
  FIXTURES=YAML.load(<<-EOS)
    :rows_initial:
      "rows_total":
      "rows_insert": "100"
      "rows_select_idx":
      "rows_update": "0"
      "rows_select_scan": "0"
      "rows_delete": "0"
    :rows_second_run:
      "rows_total": 100
      "rows_insert": "200"
      "rows_select_idx":
      "rows_update": "1"
      "rows_select_scan": "0"
      "rows_delete": "0"
    :cache_initial: 
      "xact_total": "100" 
      "xact_rollback": "50" 
      "blks_read": "10" 
      "numbackends": "4" 
      "blks_hit": "70"
      "xact_commit": "1000"
    :cache_second_run:
      "xact_total": "150" 
      "xact_rollback": "80" 
      "blks_read": "10" 
      "numbackends": "4" 
      "blks_hit": "70"
      "xact_commit": "1000"
  EOS

end