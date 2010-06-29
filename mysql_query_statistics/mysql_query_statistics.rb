# 
# Created by Eric Lindvall <eric@5stops.com>
#

require 'set'

class MysqlQueryStatistics < Scout::Plugin
  
  # needs "mysql"
  RUN_TIME = Time.now # reavaluated each run

  def build_report
    # option_value returns nil if the option value is blank
    mysql              = 'mysql'
    user               = option_value(:user) || 'root'
    password           = option_value(:password)
    host               = option_value(:host)
    port               = option_value(:port)
    socket             = option_value(:socket)
    sequential_entries = option_value(:sequential_entries).split(' ').to_set
    absolute_entries   = option_value(:absolute_entries).split(' ').to_set
    query              = 'SHOW /*!50002 GLOBAL */ STATUS'

    # mysql = Mysql.connect(host, user, password, nil, (port.nil? ? nil : port.to_i), socket)
    # result = mysql.query('SHOW /*!50002 GLOBAL */ STATUS')

    cmd = %Q[`#{mysql} --user="#{user}" --host="#{host}" --password="#{password}" --execute="#{query.gsub(/"/,'\"')}"`]
    result = eval(cmd).split("\n").collect!{|row| row.split("\t")}[1..-1]

    report_hash = {}

    total = 0
    result.each do |row| 
      key, value = row.first, row.last.to_i
      
      append_value_to_report(name, value, report_hash) if sequential_entries.include?(row.first)
      report_hash[name] = value if absolute_entries.include?(row.first)

      total += value if name =~ /^Com_/ # Com_insert Com_select Com_update Com_delete
    end

    append_value_to_report('total', total, report_hash)
    
    report(report_hash)
  end
  
  private
  
  # Returns nil if an empty string
  def option_value(opt_name)
    val = option(opt_name)
    val = (val.is_a?(String) and val.strip == '') ? nil : val
    return val
  end
  
  # Note this calculates the difference between the last run and the current run.
  def calculate_counter(name, value, current_time=RUN_TIME)
    result = nil
    # only check if a past run has a value for the specified query type
    if memory(name) && memory(name).is_a?(Hash)
      last_time, last_value = memory(name).values_at(:time, :value)
      # We won't log it if the value has wrapped
      if last_value and value >= last_value
        elapsed_seconds = current_time - last_time
        elapsed_seconds = 1 if elapsed_seconds < 1
        result = value - last_value

        # calculate per-second
        result = result / elapsed_seconds.to_f
      end
    end
    remember(name => {:time => current_time, :value => value})
    
    result
  end
  
  def append_value_to_report(name, value, report, current_time=RUN_TIME)
    squence_value = calculate_counter(now, name, value)
    report[name] = squence_value if squence_value
  end
end

