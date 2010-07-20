class StarlingMonitor < Scout::Plugin

  OPTIONS=<<-EOS
    host:
      name: Host
      notes: The host to monitor
      default: 127.0.0.1
    port:
      name: Port
      notes: The port starling is running on
      default: 61613
    queue_re:
      name: Name Reqular Expresssion
      notes: Pattern to test against queue names to select queues to monitor
      default:
    max_depth:
      name: Maximum Items
      notes: Alert if the queue contains more items than this
      default: 4000
  EOS

  attr_accessor :connection

  needs 'starling'

  def build_report
    self.connection=Starling.new("#{option(:host)}:#{option(:port)}")
    @report = {}

    begin
      connection.sizeof(:all).each do |queue_name,item_count|
        check_queue(queue_name,item_count) if should_check_queue?(queue_name)
      end
      report(@report)
    rescue Exception=>e
      error("Got unexpected error: #{e} #{e.class}")
    end
  end

  def should_check_queue?(name)
    option(:queue_re).nil? or /#{option(:queue_re)}/ =~ name
  end

  def check_queue(name,depth)
    q_depth = (depth||0).to_i
    @report ||= {}
    @report[name] = q_depth
    if q_depth > option(:max_depth).to_i
      alert("Max Queue Depth for #{name} exceeded","#{q_depth} items is more than the max allowed #{option(:max_depth)}")
    end
  end

end

