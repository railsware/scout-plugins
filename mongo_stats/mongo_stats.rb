class MongoStats < Scout::Plugin
  OPTIONS=<<-EOS
    path_to_db_yml:
      label: Path to database.yml
    rails_env:
      label: Rails Environment
      default: production
  EOS

  needs 'mongo', 'yaml'

  def build_report 
    # check if database.yml path provided
    if option('path_to_db_yml').nil? or option('path_to_db_yml').empty?
      return error("The path to the database.yml file was not provided.","Please provide the full path to the MongoDB database file (ie - /var/www/apps/APP_NAME/current/config/database.yml)")
    end
    
    # check if database.yml loads
    begin
      yaml = YAML::load_file(option('path_to_db_yml'))
    rescue Errno::ENOENT
      return error("Unable to find the database.yml file", "Could not find a MongoDB config file at: #{option(:path_to_db_yml)}. Please ensure the path is correct.")
    end
    
    # Try to open a connection to Mongo
    config     = yaml[option('rails_env')]
    begin
      connection = Mongo::Connection.new(config['host'], config['port'])
    rescue Mongo::ConnectionFailure
      return error("Unable to connect to the MongoDB Daemon.","Please ensure it is running on #{config['host']}:#{config['port']}")
    end
    
    # Try to connect to the database
    db         = connection.db(config['database'])
    begin 
      db.authenticate(config['username'], config['password']) unless config['username'].nil?
    rescue Mongo::AuthenticationError
      return error("Unable to authenticate to MongoDB Database.",$!.message)
    end
    stats = db.stats

    report(:objects      => stats['objects'])
    report(:data_size    => stats['dataSize'])
    report(:storage_size => stats['storageSize'])
    report(:indexes      => stats['indexes'])
    report(:index_size   => stats['indexSize'])
  end
end