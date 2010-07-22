# 
# Created by Eric Lindvall <eric@5stops.com>
#

class MysqlStatistics < Scout::Plugin
  
  require "open3"
  attr_accessor :run_time
  
  def initialize(last_run, memory, options)
    @run_time = Time.now
    super
  end

  def build_report
    result = show_status_result
    report( calculate_statistics( result ) ) if result
  end
  
  def calculate_statistics(result)
    sequential_entries = option(:sequential_entries).to_s.strip.split(' ')
    absolute_entries   = option(:absolute_entries).to_s.strip.split(' ')

    report_hash = {}

    total = 0
    result.each do |row| 
      key, value = row.split("\t")
      value = value.to_i
      
      append_value_to_report(key, value, report_hash) if sequential_entries.include?(key)
      report_hash[key] = value if absolute_entries.include?(key)

      total += value if key =~ /^Com_/ # Com_insert Com_select Com_update Com_delete
    end

    append_value_to_report('total', total, report_hash)

    report_hash
  end
  
  private
  
  def show_status_result
    # option_value returns nil if the option value is blank
    mysql              = 'mysql'
    user               = option_value(:user) || 'root'
    password           = option_value(:password)
    host               = option_value(:host)
    port               = option_value(:port)
    socket             = option_value(:socket)
    query              = 'SHOW /*!50002 GLOBAL */ STATUS'

    # mysql = Mysql.connect(host, user, password, nil, (port.nil? ? nil : port.to_i), socket)
    # result = mysql.query('SHOW /*!50002 GLOBAL */ STATUS')

    cmd = %Q[#{mysql} --execute="#{query.gsub(/"/,'\"')}" --user="#{user}" --host="#{host}" --port="#{port}" --password="#{password}" --socket="#{socket}" | tail -n +2]
    
    output, error = Open3.popen3(cmd) { |stdin, stdout, stderr| [stdout.gets.chomp, stderr.gets.chomp] }
    
    error = "no result was retreived by the command : \n#{cmd}" if (output.nil? || output.empty?) && (error.nil? || error.empty?)

    error(:subject => "errors while getting mysql stats", :body => error) and return nil if error
    
    output.split("\n")
  end
  
  # Returns nil if an empty string
  def option_value(opt_name)
    val = option(opt_name)
    val = (val.is_a?(String) and val.strip == '') ? nil : val
    return val
  end
  
  # Note this calculates the difference between the last run and the current run.
  def calculate_counter(name, value, current_time=nil)
    current_time ||= run_time()
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
  
  def append_value_to_report(name, value, report, current_time=nil)
    current_time ||= run_time()
    squence_value = calculate_counter(name, value, current_time)
    report[name] = squence_value if squence_value
  end
end

