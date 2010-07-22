# Created by Eric Lindvall <eric@5stops.com>

class MysqlQueryStatistics < Scout::Plugin
  ENTRIES = %w(Com_insert Com_select Com_update Com_delete)

  OPTIONS=<<-EOS
  user:
    name: MySQL username
    notes: Specify the username to connect with
    default: root
  password:
    name: MySQL password
    notes: Specify the password to connect with
  host:
    name: MySQL host
    notes: Specify something other than 'localhost' to connect via TCP
    default: localhost
  port:
    name: MySQL port
    notes: Specify the port to connect to MySQL with (if nonstandard)
  socket:
    name: MySQL socket
    notes: Specify the location of the MySQL socket
  EOS

  needs "mysql"

  def build_report
    # option_value returns nil if the option value is blank
    mysql              = 'mysql'
    user               = option_value(:user) || 'root'
    password           = option_value(:password)
    host               = option_value(:host)
    port               = option_value(:port)
    socket             = option_value(:socket)
    sequential_entries = option(:sequential_entries).to_s.strip.split(' ').to_set
    absolute_entries   = option(:absolute_entries).to_s.strip.split(' ').to_set
    query              = 'SHOW /*!50002 GLOBAL */ STATUS'

    # mysql = Mysql.connect(host, user, password, nil, (port.nil? ? nil : port.to_i), socket)
    # result = mysql.query('SHOW /*!50002 GLOBAL */ STATUS')

    cmd = %Q[`#{mysql} --execute="#{query.gsub(/"/,'\"')}" --user="#{user}" --host="#{host}" --port="#{port}" --password="#{password}" --socket="#{socket}"`]
    
    result = eval(cmd).split("\n")[1..-1]
    
    report_hash = {}

    total = 0
    result.each do |row| 
      key, value = row.split("\t")
      value = value.to_i
      
      append_value_to_report(key, value, report_hash) if sequential_entries.include?(key)
      report_hash[key] = value if absolute_entries.include?(key)

    report_hash = {}
    rows.each do |row|
      name = row.first[/_(.*)$/, 1]
      value = counter(now, name, row.last.to_i)
      # only report if a value is calculated
      next unless value
      report_hash[name] = value
    end

    total_val = counter(now, 'total', total)
    report_hash['total'] = total_val if total_val
    
    report(report_hash)
  end
  
  def test(a)
  end
  
  private
  
  # Returns nil if an empty string
  def option_value(opt_name)
    val = option(opt_name)
    return (val.is_a?(String) and val.strip == '') ? nil : val
  end

end

