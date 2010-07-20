$VERBOSE=false

class ResqueStats < Scout::Plugin

  needs 'redis', 'resque'

  OPTIONS=<<-EOS
  redis:
    name: Resque.redis
    notes: "Redis connection string: 'hostname:port' or 'hostname:port:db'"
    default: localhost:6379
  namespace:
    name: Namespace
    notes: "Resque namespace: 'resque:production'"
    default:
  EOS

  def build_report
    Resque.redis = option(:redis)
    Resque.redis.namespace = option(:namespace)
    info = Resque.info
    report(
      :working => info[:working],
      :pending => info[:pending],
      :total_failed  => info[:failed],
      :queues  => info[:queues],
      :workers => info[:workers]
    )
    counter(:processed, info[:processed], :per => :second)
    counter(:failed, info[:failed], :per => :second)
    Resque.queues.each do |queue|
      report("#{queue}" => Resque.size(queue))
    end
  end

end