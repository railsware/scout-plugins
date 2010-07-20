require File.dirname(__FILE__)+"/../test_helper"
require File.dirname(__FILE__)+"/mongo_stats"
require 'mongo'

class MongoStatsTest < Test::Unit::TestCase
  
  def setup
    @options=parse_defaults("mongo_stats")
    Mongo::Connection.any_instance.stubs(:initialize).returns(Mongo::DB.new('localhost','27017'))
  end
  
  def test_should_error_without_yaml_file
    plugin=MongoStats.new(nil,{},@options)
    res=plugin.run
    assert res[:errors].first[:subject] =~ /not provided/
  end
  
  def test_should_error_with_invalid_yaml_path
    plugin=MongoStats.new(nil,{},@options.merge({:path_to_db_yml => 'invalid'}))
    res=plugin.run
    assert res[:errors].first[:subject] =~ /Unable to find/
  end
  
  def test_should_parse_stats    
    plugin=MongoStats.new(nil,{},@options.merge({:path_to_db_yml => 'fixtures/database.yml'}))
    Mongo::DB.any_instance.stubs(:stats).returns(STATS)
    res=plugin.run
    assert_equal STATS['objects'], res[:reports].find { |r| r.keys.include?(:objects)}[:objects],200
  end
  
  STATS = {"collections"=>2, "objects"=>200, "dataSize"=>92, "storageSize"=>5632, "numExtents"=>2, 
    "indexes"=>1, "indexSize"=>8192, "ok"=>1.0}
end