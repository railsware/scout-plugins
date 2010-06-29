class PostgresqlMonitoring< Scout::Plugin
  # need the ruby-pg gem
  needs 'pg'
  
  OPTIONS=<<-EOS
    user:
      name: PostgreSQL username
      notes: Specify the username to connect with
    password:
      name: PostgreSQL password
      notes: Specify the password to connect with
    host:
      name: PostgreSQL host
      notes: Specify the host name of the PostgreSQL server. If the value begins with
              a slash it is used as the directory for the Unix-domain socket. An empty
              string uses the default Unix-domain socket.
      default: localhost
    dbname:
      name: Database
      notes: The database name to monitor
      default: postgres
    port:
      name: PostgreSQL port
      notes: Specify the port to connect to PostgreSQL with
      default: 5432
  EOS

  NON_COUNTER_ENTRIES = ["numbackends"]
  
  def build_report
    now = Time.now
    report = {}
    
    begin
      pgconn = PGconn.new(:host=>option(:host), :user=>option(:user), :password=>option(:password), :port=>option(:port).to_i, :dbname=>option(:dbname))
    rescue PGError => e
      return errors << {:subject => "Unable to connect to PostgreSQL.",
                        :body => "Scout was unable to connect to the PostgreSQL server: #{e.backtrace}"}
    end
    result = pgconn.exec('SELECT sum(idx_tup_fetch) AS "rows_select_idx", 
                                 sum(seq_tup_read) AS "rows_select_scan", 
                                 sum(n_tup_ins) AS "rows_insert", 
                                 sum(n_tup_upd) AS "rows_update",
                                 sum(n_tup_del) AS "rows_delete",
                                 (sum(idx_tup_fetch) + sum(seq_tup_read) + sum(n_tup_ins) + sum(n_tup_upd) + sum(n_tup_del)) AS "rows_total"
                          FROM pg_stat_all_tables;')
    row = result[0]

    row.each do |name, val|
      if NON_COUNTER_ENTRIES.include?(name)
        report[name] = val.to_i
      else
        counter(name,val.to_i,:per => :second)
      end
    end

    result = pgconn.exec('SELECT sum(numbackends) AS "numbackends", 
                                 sum(xact_commit) AS "xact_commit", 
                                 sum(xact_rollback) AS "xact_rollback", 
                                 sum(xact_commit+xact_rollback) AS "xact_total", 
                                 sum(blks_read) AS "blks_read", 
                                 sum(blks_hit) AS "blks_hit"
                          FROM pg_stat_database;')
    row = result[0]
    row.each do |name, val|
      if NON_COUNTER_ENTRIES.include?(name)
        report[name] = val.to_i
      else
        counter(name, val.to_i, :per => :second)
      end
    end

    if row['blks_hit'] and row['blks_read']
      report['blks_cache_pc'] = (row['blks_hit'].to_f / (row['blks_hit'].to_f+row['blks_read'].to_f) * 100).to_i
    else
      report['blks_cache_pc'] = nil
    end

    report(report) if report.values.compact.any?
  end
end