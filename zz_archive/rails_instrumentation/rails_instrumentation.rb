class RailsInstrumentation < Scout::Plugin
  # These are fields that need to be averaged
  AVG_FIELDS = %w(render_runtime_avg db_runtime_avg runtime_avg other_runtime_avg)
  # These are fields where the max value will be kept
  MAX_FIELDS = %w(runtime_max other_runtime_max render_runtime_max db_runtime_max)
  
  # This assembles 1 report for each action, 1 high-level summary report, and adds any hints. 
  #
  # For example, if a single processing is serving the Rails app, the agent reports every
  # 3 minutes, and the same action is requested every 30 seconds (and it's the only request),
  # 1 report will be created for the action-specific data and another with the summary data. 
  #
  # If 2 processes are serving the app but with the exact same conditions, the same number
  # of reports is created. 
  #
  # If another unique action is requested, then another report will be created (total of 3 reports).
  def build_report
    # intialize our analyzer 
    analyzer = RailsAnalyzer.new
    
    # these hold report data while messages are parsed
    @report_data = Hash.new
    @summary_data = {'num_requests' => 0,'avg_request_time_sum' => 0,'scout_time' => nil}
    
    ### pull in the reports from the message queue and analyze each report
    each_queued_message do |message, time|
      merge_summary_data(message)
      
      # from all of the reports, creates 1 report for each action.       
      actions = message['actions']
      
      # associates the time w/each action
      actions.each { |k,v| v.merge!( 'scout_time' => get_time(message) ) }
      actions.each do |k,v|
        # if the action hasn't been aggregated yet, add it. otherwise, 
        # merge in the data.
        if @report_data[k].nil?
          @report_data[k] = v
        else
          merge_data(k,v)
        end # if @report_data[k].nil?
      end # actions.each do |k,v|
      
      analyzer.analyze(message)
    end
    
    # if no requests, exit
    return if @summary_data['num_requests'].zero?
    
    average_summed_data
    # create reports for actions
    create_action_reports
    # add in summary data
    create_summary_report
    # create hints based on analysis
    analyzer.finish!
    analyzer.hints.each { |h| hint(h) }
  end
  
  # Updates the summary report with data from the most recent message. 
  def merge_summary_data(message)
    @summary_data['num_requests'] += message['num_requests']
    @summary_data['avg_request_time_sum'] += message['avg_request_time']*message['num_requests']
    @summary_data['scout_time'] = message['scout_time']
  end
  
  # Older versions of the rails instrumentation plugin use +time+, newer versions use +scout_time+. 
  def get_time(message)
    message['scout_time'] || message['time']
  end
  
  # Merges data from the +k+ controller/action as the value.
  def merge_data(k,v)
    data = @report_data[k]
    
    # MAX FIELDS
    # compares the value for each of these fields with the existing value, keeping the max value
    MAX_FIELDS.each do |field|
      if v[field] and (v[field] > data[field]) 
        data[field] = v[field]
        # marks the maximum runtime w/the scout_time - needed for peak triggers on runtime_max
        if field == 'runtime_max'
          data['scout_time'] = v['scout_time']
        end
      end
    end

    # AVERAGE FIELDS
    # sum the values of these ... before reporting, divide by the num_requests to record avg, 
    # dropping the sum key
    AVG_FIELDS.each do |field|
      data[field+'_sum'] ||= data[field]*data['num_requests']
      data[field+'_sum'] += v[field]*v['num_requests']
    end

    # SUM FIELDS
    %w(num_requests).each do |field|
      data[field] += v[field]
    end

    @report_data[k] = data
  end # end merge_data
  
  # For all fields that contains averages, divides the sum by / num_requests to obtain
  # the final average.
  def average_summed_data
    AVG_FIELDS.each do |field|
      @report_data.each do |action,data|
        if sum = data.delete(field+'_sum')
          data[field] = sum/data['num_requests']
        end
      end
    end
  end # end average_summed_data
  
  def create_action_reports
    @report_data.each do |k,v|
      time = v.delete('scout_time')
      data = {'actions' => {k => v}, 'scout_time' => time}
      report(data)
    end
  end # end create_action_reports

  # Builds up the summary data:
  # - num_requests
  # - avg_request_time
  # - scout_time (most recent)
  def create_summary_report
    sum = @summary_data.delete('avg_request_time_sum')
    @summary_data['avg_request_time'] = sum/@summary_data['num_requests']
    report(@summary_data)
  end
end # Scout::Plugin

require "digest/md5"

# Accepts a Query Array (which contains details on an SQL Query). This is a wrapper
# to make SQL queries easier to work with.
class SqlQuery
  attr_accessor :query_type, :extra, :key, :rows, :table, :sql, :sanitized_sql, :duration, :time_of_day,
                :explain_issues
  
  #####################
  ### Class Methods ###
  #####################
  
  # Initializes a new +SqlQuery+ and analyzes the query. Returns a 3 element Hash:
  def self.analyze(query_array)
    query = new(query_array)
    query.analyze_explain
    query
  end
  
  # From Rails Query Review Plugin
  def self.sanitize_sql(sql)
    # TODO - See why this isn't a string
    return "Unable to sanitize SQL" if !sql.is_a?(String)
    new_sql = sql.dup 
    new_sql.gsub!(/\b(?:0x[0-9A-Fa-f]+|\d+)\b/, "?")
    new_sql.gsub!(/'(?>[^']*)(?>''[^']*)*'/,    "?")
    new_sql.gsub!(/"(?>[^"]*)(?>""[^"]*)*"/,    "?")
    return new_sql
  end
  
  ########################
  ### Instance Methods ###
  ########################
  
  def initialize(query_array)
    # Sets EXPLAIN output to specific attributes for easier access
    explain_hash = query_array.last
    if explain_hash.is_a?(Hash)
      self.query_type = explain_hash['type']
      self.extra      = explain_hash['extra'] || ''
      self.key = explain_hash['key']
      self.rows = explain_hash['rows']
      self.table = explain_hash['table']
    end
    self.sql = query_array[1]
    self.sanitized_sql = self.class.sanitize_sql(sql)
    self.duration = query_array.first || 0
    self.time_of_day = query_array[2]
    self.explain_issues = Array.new
  end
  
  # True if any EXPLAIN output. 
  def explained?
    query_type or extra or key or rows or table
  end
  
  # Returns true if this Query has..issues...it's either slow or slow w/bad things
  # found when analyzing the EXPLAIN output.
  #
  # If a query isn't slow, but has EXPLAIN issues, it's not a problem because it isn't 
  # slow yet. We only want to create hints for problems, not for things that are 
  # likely to be ignored.
  def problems?
    slow? or (slow? and explain_issues?)
  end
  
  def explain_issues?
    explain_issues.any?
  end
  
  # Returns +true+ if the query duration exceeds RailsAnalyzer::MAX_QUERY_TIME.
  def slow?
    duration > RailsAnalyzer::MAX_QUERY_TIME
  end
  
  # Analyzes the explain output of the query. If any issues are detected, they are added to the
  # explain_issues Array.
  def analyze_explain
    analyze_query_type
    analyze_key
  end

  def analyze_query_type
    case query_type
    when "system", "const", "eq_ref" 
      # these are good
    when "ref", "ref_or_null", "range", "index_merge" 
      # also good
    when "unique_subquery", "index_subquery"
      #NOT SURE
    when "index" 
      self.explain_issues << "using a full index tree scan (slightly faster than a full table scan)" if extra.include?("using where")
    when "all" 
      self.explain_issues << "using a full table scan" if extra.include?("using where")
    end
  end

  def analyze_key
    return unless explained?
    if self.key == "const"
      # good
    elsif self.key.nil? && !self.extra.include?("select tables optimized away")
      self.explain_issues <<  "not using an index, which meant scanning #{self.rows} rows in the <em>#{table}</em> table"
    end
  end  
end # SqlQuery

class RailsAnalyzer
  # in milliseconds
  MAX_QUERY_TIME = 50
  # if more than this number of queries are generated from an action, a hint is generated. 
  MAX_QUERIES = 10
  
  attr_accessor :actions, :time, :actions_with_too_many_queries, :hints
  
  def initialize
    self.hints  = Array.new
    reset!
  end
  
  # Wraps up the analysis, generating hints and reseting counts.
  def finish!
    create_query_hints
    create_too_many_queries_hints
  end
  
  # Analyzes a Scout report, populating +actions+ with actions & associated problem queries and 
  # +actions_with_too_many_queries+ with actions that have too many queries.
  #
  # Queries is an Array of Arrays of Arrays:
  # - Top Level => An element for each request generated for the +action+.
  #                For example, if the users/show action processed 5 requests, there would be 5 array elements.
  # - 2nd Level => An element for each query of the request. 
  #                For example, if the request had 20 queries, there would be 20 elements
  # - 3rd level => An element that corresponds to specific attributes of the query.
  #                These SQL Queries contain the following elements at each index:
  #                0 - Length of query in MS
  #                1 - SQL
  #                2 - Time of Day of Query
  #                3 - EXPLAIN output in a Hash
  def analyze(o)
    # grab the time the report was generated
    self.time=o.delete('time')
    actions = o['actions']
    actions.each_pair do |action,data|
      request_groups=data.delete('queries') 
      next if request_groups.nil? # If no queries, move on to the next action
      request_groups.each do |queries|
        # Look at each query, analyzing it for problems. If any problems occur,
        # add the query to the list of problem queries for the +action+.
        queries.each do |(time, query_lookup_id, *rest)|
          # queries are abstracted into a lookup table, so we pull in the
          # actual query from this lookup table before analyzing it.
          query_and_time = [time, o['queries'][query_lookup_id], *rest]
          analyzed_query = SqlQuery.analyze(query_and_time)
          add_problem_query(action,analyzed_query) if analyzed_query.problems?
        end # queries.each
        analyze_too_many_queries(action,queries)
      end # request_groups
    end # o.each_pair
  end # analyze
  
  # Creates a hint for each problem query
  def create_query_hints
    if actions.any?
      actions.each do |action,queries|
        queries.each do |query|
          duration=query.duration.to_i
          if query.explain_issues? # slow & explain issues. we can give more details.
            importance = 0
            importance += 1 if duration > 600
            importance += 1 if duration > 900
            importance += 1 if duration > 1200
            importance = 3 if importance > 3 # importance maxes out at 3
            add_hint(
                  :title => "A #{duration}ms query in the #{query.table} table may be able to be optimized.",
                  :description => "The query #{query.explain_issues.size > 1 ? 'has the following issues:' : 'is'} #{query.explain_issues.join(', ')}",
                  :grouping => action,
                  :token => "explain #{query.sanitized_sql}",
                  :additional_info => query.sanitized_sql,
                  :importance=>importance,
                  :tag_list=>'slow,explain_issues'
                  
            )
          else # just slow
            # calculate importance
            importance = 0
            importance += 1 if duration > 600
            importance += 1 if duration > 900
            importance += 1 if duration > 1200
            add_hint(
                  :title => "A slow query occurred (#{duration} ms).",
                  :description => "This query exceeds the maximum specified duration of #{MAX_QUERY_TIME}ms.",
                  :grouping => action,
                  :token => "slow #{query.sanitized_sql}",
                  :additional_info => query.sanitized_sql,
                  :importance=>importance,
                  :tag_list=>'slow'
            )
          end
        end
      end
    end # actions.any?
  end
  
  # Creates a hint for each action that exceeded the maximum num. of queries. 
  def create_too_many_queries_hints
    return unless actions_with_too_many_queries.any?
    actions_with_too_many_queries.each do |q|
      title = "The #{q[:action]} action has too many SQL Queries."
      count,time=q[:query_count],q[:db_time].to_i
      description = "This action exceeded the maxiumum number of SQL queries with #{count} queries totaling #{time}ms of DB time."
      # calculate importance
      importance = 0
      importance += 1 if count > 15
      importance += 1 if count > 25
      importance += 1 if time > 100
      importance += 1 if time > 400
      importance = 3 if importance > 3 # importance maxes out at 3
      add_hint(:title => title,
           :description => description,
           :grouping => q[:action],
           :token => 'too many queries' + q[:query_count].to_s,
           :importance=> importance,
           :tag_list=>'too_many_queries'
          )
    end
  end
  
  def add_hint(options = {})
    options = {
      :time => time,
      :kind => :sql
    }.merge(options)
    options[:token] = Digest::MD5.hexdigest(options[:token])
    self.hints << options
  end
  
  def reset!
    self.actions                       = {}
    self.actions_with_too_many_queries = Array.new
  end
  
  # Adds the +ScoutPlugin::SqlQuery+ to the Array of slow queries for the +action+.
  def add_problem_query(action,analyzed_query)
    existing_queries = actions[action]
    if existing_queries and !existing_queries.find { |q| q.sanitized_sql == analyzed_query.sanitized_sql }
      actions[action] << analyzed_query
    else
      actions[action] = [ analyzed_query ]
    end
  end
  
  # Iterates thru each of the collections of SQL queries, generating a hint if 
  # the number of SELECT queries exceeds +MAX_QUERIES+.
  def analyze_too_many_queries(action,queries)
    query_count = queries.size
    if query_count >= MAX_QUERIES
      max_db_time = queries.inject(0) { |sum,q| sum + q.first }
      # add this action as one with slow queries.
      # If the action doesn't already exist in the Array, add it. 
      # Delete the existing action if it exists and its DB time is less than this +action+.
      # * The action exists,
      if actions_with_too_many_queries.find { |hash| hash[:action] == action }.nil? or actions_with_too_many_queries.delete_if { |hash| hash[:action] == action and hash[:db_time] < max_db_time}.is_a?(Hash)
        actions_with_too_many_queries << {:action => action, 
                                          :query_count => query_count, 
                                          :db_time => max_db_time
                                          }
      end # if actions_with_too_many_queries
    end # if query_count >= MAX_QUERIES
  end # analyze_too_many_queries
end

### Support

class Fixnum
  # TODO - Add me
  def commify
    self
  end
end
