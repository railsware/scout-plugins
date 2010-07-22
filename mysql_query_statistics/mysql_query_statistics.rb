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
    # get_option returns nil if the option value is blank
    user     = get_option(:user) || 'root'
    password = get_option(:password)
    host     = get_option(:host)
    port     = get_option(:port)
    socket   = get_option(:socket)
    
    now = Time.now
    mysql = Mysql.connect(host, user, password, nil, (port.nil? ? nil : port.to_i), socket)
    result = mysql.query('SHOW /*!50002 GLOBAL */ STATUS')
    rows = []
    total = 0
    result.each do |row| 
      rows << row if ENTRIES.include?(row.first)

      total += row.last.to_i if row.first[0..3] == 'Com_'
    end
    result.free

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

  private
  
  # Returns nil if an empty string
  def get_option(opt_name)
    val = option(opt_name)
    return (val.is_a?(String) and val.strip == '') ? nil : val
  end

end

