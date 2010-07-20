#
# Provides an overview of basic server health:
#
# * Memory
# * Disk Usage
# * CPU load
#
#
# Options Supported: disk_command, num_processors (leave blank to auto-detect)
#
class Overview < Scout::Plugin

  OPTIONS=<<-EOS
  options:
    disk_command:
      name: df Command
      notes: The command used to display free disk space
      default: "df -h"
    disk_filesystem:
      name: Filesystem
      notes: The filesystem to check usage, if none specified, uses the first listed
      default:
    num_processors:
      name: Number of Processors
      notes: For calculating CPU load. If left blank, autodetects through /proc/cpuinfo
      default: 1
  EOS
  
  # memory contants
  UNITS = { "b" => 1,
            "k" => 1024,
            "m" => 1024 * 1024,
            "g" => 1024 * 1024 * 1024 }

  # Disk usage constants -- the Disk Freespace RegEx
  DF_RE = /\A\s*(\S.*?)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*\z/


  def build_report
    reports=Hash.new
    reports.merge!(do_disk_usage())
    reports.merge!(do_cpu_load())
    reports.merge!(do_memory())

    report(reports)
  end



  private

  # ----------------------------------------------------
  # Memory
  def do_memory
    # will be passed at the end to report to Scout
    report_data = Hash.new

    mem_info = {}
    `cat /proc/meminfo`.each_line do |line|
      _, key, value = *line.match(/^(\w+):\s+(\d+)\s/)
      mem_info[key] = value.to_i
    end

    # memory info is empty - operating system may not support it (why doesn't an exception get raised earlier on mac osx?)
    if mem_info.empty?
      raise "No such file or directory"
    end

    mem_total = mem_info['MemTotal'] / 1024
    mem_free = (mem_info['MemFree'] + mem_info['Buffers'] + mem_info['Cached']) / 1024
    mem_used = mem_total - mem_free
    mem_percent_used = (mem_used / mem_total.to_f * 100).to_i

    swap_total = mem_info['SwapTotal'] / 1024
    swap_free = mem_info['SwapFree'] / 1024
    swap_used = swap_total - swap_free
    unless swap_total == 0
      swap_percent_used = (swap_used / swap_total.to_f * 100).to_i
    end

    report_data[:mem_total] = mem_total
    report_data[:mem_used] = mem_used
    report_data[:mem_used_percent] = mem_percent_used

    report_data[:mem_swap_total] = swap_total
    report_data[:mem_swap_used] = swap_used
    unless  swap_total == 0
      report_data[:mem_swap_percent] = swap_percent_used
    end


  rescue Exception => e
    if e.message =~ /No such file or directory/
      error('Unable to find /proc/meminfo',%Q(Unable to find /proc/meminfo. Please ensure your operationg system supports procfs:
         http://en.wikipedia.org/wiki/Procfs)
      )
    else
      raise
    end
  ensure
    return report_data
  end

  #---------------------------------------------------------
  # Disk Usage

 def do_disk_usage
    ENV['lang'] = 'C' # forcing English for parsing
    df_command   = option(:disk_command) || "df -h"
    df_output    = `#{df_command}`

    df_lines = []
    parse_file_systems(df_output) { |row| df_lines << row }

    # if the user specified a filesystem use that
    df_line = nil
    if option(:disk_filesystem)
      df_lines.each do |line|
        if line.has_value?(option(:disk_filesystem))
          df_line = line
        end
      end
    end

    # else just use the first line
    df_line ||= df_lines.first

    # remove 'filesystem' and 'mounted on' if present - these don't change.
    df_line.reject! { |name,value| ['filesystem','mounted on'].include?(name.downcase.gsub(/\n/,'')) }

    # capacity on osx = Use% on Linux ... convert anything that isn't size, used, or avail to capacity ... a big assumption?
    assumed_capacity = df_line.find { |name,value| !['size','used','avail'].include?(name.downcase.gsub(/\n/,''))}
    df_line.delete(assumed_capacity.first)
    df_line['capacity'] = assumed_capacity.last

    # will be passed at the end to report to Scout
    report_data = Hash.new

    df_line.each do |name, value|
      report_data["disk_#{name.downcase.strip}".to_sym] = clean_value(value)
    end
    return report_data
  end


  # Parses the file systems lines according to the Regular Expression
  # DF_RE.
  #
  # normal line ex:
  # /dev/disk0s2   233Gi   55Gi  177Gi    24%    /

  # multi-line ex:
  # /dev/mapper/VolGroup00-LogVol00
  #                        29G   25G  2.5G  92% /
  #
  def parse_file_systems(io, &line_handler)
    line_handler ||= lambda { |row| pp row }
    headers      =   nil

    row = ""
    io.each_line do |line|
      if headers.nil? and line =~ /\AFilesystem/
        headers = line.split(" ", 6)
      else
        row << line
        if row =~  DF_RE
          fields = $~.captures
          line_handler[headers ? Hash[*headers.zip(fields).flatten] : fields]
          row = ""
        end
      end
    end
  end

  # Ensures disk space metrics are in GB. Metrics that don't contain 'G,M,or K' are just
  # turned into integers.
  def clean_value(value)
    if value =~ /G/i
      value.to_f
    elsif value =~ /M/i
      (value.to_f/1024.to_f).round
    elsif value =~ /K/i
      (value.to_f/1024.to_f/1024.to_f).round
    else
      value.to_f
    end
  end


  #-----------------------------------------------------
  # CPU Load
  def do_cpu_load
    result={}
    begin
      if `uptime` =~ /load average(s*): ([\d.]+)(,*) ([\d.]+)(,*) ([\d.]+)\Z/
        result = {:cpu_last_minute          => $2.to_f/get_num_processors,
                  :cpu_last_five_minutes    => $4.to_f/get_num_processors,
                  :cpu_last_fifteen_minutes => $6.to_f/get_num_processors}
      else
        raise "Couldn't use `uptime` as expected."
      end
    rescue Exception
      error "Error determining load", $!.message
    end

    return result
  end

  def get_num_processors
    # first, check if the options provided is > 0. So leave the options blank to auto-detect
    processors = option('num_processors').to_i
    return processors if processors > 0

    # otherwise, pull it from memory
    processors = memory(:processors)

    # if we didn't get it from memory, try to auto-detect through /proc/cpuinfo
    unless processors && processors > 0
      if `cat /proc/cpuinfo | grep 'model name' | wc -l` =~ /(\d+)/
        processors = $1.to_i
      else
        raise "Couldn't use /proc/cpuinfo as expected."
      end
      raise "Couldn't use /proc/cpuinfo as expected." unless processors > 0
    end
    remember(:processors, processors)
    return processors
  end

end




