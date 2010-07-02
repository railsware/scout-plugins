require File.dirname(__FILE__) + '/../spec/spec_helper'
require File.dirname(__FILE__) + '/aws_cloudwatch'
require 'fakeweb'

describe AwsCloudwatch do

  LABELS = {
      "StorageSpace" => "GBytes",
      "CPUUtilization" => "Percent",
      "DatabaseConnections" => "Count",
      "FreeStorageSpace" => "Bytes",
      "ReadIOPS" => "Count/Second",
      "WriteIOPS" => "Count/Second",
      "ReadLatency" => "Seconds",
      "WriteLatency" => "Seconds",
      "ReadThroughput" => "Bytes/Second",
      "WriteThroughput" => "Bytes/Second"
      }

  # it "should run for RDS" do
  before(:all) do
    current_run = Time.now
    last_run = current_run - 3*60
    memory   = {}
    options  = {:aws_access_key => '0B5MN90FYXXKWR8S17G2', :aws_secret =>  '80dRHe6NSdBdt/Tz0P6qrSg6XgM2KKMkFxT4bUzK', :dimension => 'rp-tracking-service',:namespace => 'AWS/RDS'}

    plugin = AwsCloudwatch.new(last_run, memory, options)

    @random_label_values = {}

    FakeWeb.allow_net_connect = false

    [ LABELS - ['StorageSpace'] ].each do |label, unit|
      @random_label_values[label] = random_value = Kernel.rand*100000.0
      FakeWeb.register_uri(:get, %r|https://monitoring\.amazonaws\.com.*?#{label}|, :body => <<-EOF)
<GetMetricStatisticsResponse xmlns="http://monitoring.amazonaws.com/doc/2009-05-15/">
  <GetMetricStatisticsResult>
    <Datapoints>
      <member>
        <Timestamp>#{Time.now.strftime('%Y-%m-%dT%H:%M:%SZ')}</Timestamp>
        <Unit>#{unit}</Unit>
        <Samples>5.0</Samples>
        <Average>#{random_value}</Average>
      </member>
    </Datapoints>
    <Label>#{label}</Label>
  </GetMetricStatisticsResult>
  <ResponseMetadata>
    <RequestId>ceded9a9-85da-11df-a662-69fbdd7a7fe8</RequestId>
  </ResponseMetadata>
</GetMetricStatisticsResponse>
EOF
    end

    @random_label_values['StorageSpace'] = random_value = Kernel.rand*100000.0
    FakeWeb.register_uri(:get, %r|https://rds.amazonaws.com/|, :body => <<-EOF)
<GetMetricStatisticsResponse xmlns="http://monitoring.amazonaws.com/doc/2009-05-15/">
  <GetMetricStatisticsResult>
    <Datapoints>
      <member>
        <Timestamp>#{Time.now.strftime('%Y-%m-%dT%H:%M:%SZ')}</Timestamp>
        <Unit>Giga Bytes</Unit>
        <Samples>5.0</Samples>
        <Average>#{random_value}</Average>
      </member>
    </Datapoints>
    <Label>StorageSpace</Label>
  </GetMetricStatisticsResult>
  <ResponseMetadata>
    <RequestId>ceded9a9-85da-11df-a662-69fbdd7a7fe8</RequestId>
  </ResponseMetadata>
</GetMetricStatisticsResponse>
EOF

  
    plugin.build_report
    @report_hash = plugin.data_for_server[:reports].inject({}){|r,d|r.merge!(d)}
    puts @report_hash.inspect
    puts @random_label_values.inspect
    
  end
  
  [ LABELS.keys - ["FreeStorageSpace"] ].each do |label| 
    it "should receive the right value for #{label}" do
      @report_hash[label].class.should == @random_label_values[label].class
      @report_hash[label].to_s.should == @random_label_values[label].to_s
    end    
  end

  it "should receive the right value for FreeStorageSpace" do
    free_storage_space = @random_label_values["FreeStorageSpace"]
    free_storage_space = free_storage_space / (1024 * 1024 * 1024)
    storage_space      = @random_label_values["StorageSpace"]
    used_storage_space = storage_space - free_storage_space


    @report_hash["StorageSpace"].to_s.should          == storage_space.to_s
    @report_hash["FreeStorageSpace"].to_s.should      == value.to_s
    @report_hash["UsedStorageSpace"].to_s.should      == used_storage_space.to_s
    @report_hash["StorageSpace capacity"].to_s.should == (used_storage_space / storage_space * 100).to_s
  end    
  
  
end



# {"Action"=>"GetMetricStatistics", "Dimensions.member.1.Value"=>"rp-tracking-service", "Version"=>"2009-05-15", "MeasureName"=>"WriteThroughput", "AWSAccessKeyId"=>"0B5MN90FYXXKWR8S17G2", "Period"=>"300", "SignatureVersion"=>"1", "Timestamp"=>"2010-07-02T13:07:46Z", "Namespace"=>"AWS/RDS", "StartTime"=>"2010-07-02T13:02:38+00:00", "Dimensions.member.1.Name"=>"DBInstanceIdentifier", "Statistics.member.1"=>"Average", "EndTime"=>"2010-07-02T13:07:38+00:00"}
# params:
# nil
# request address : https://monitoring.amazonaws.com:443/?AWSAccessKeyId=0B5MN90FYXXKWR8S17G2&Action=GetMetricStatistics&Dimensions.member.1.Name=DBInstanceIdentifier&Dimensions.member.1.Value=rp-tracking-service&EndTime=2010-07-02T13%3A07%3A38%2B00%3A00&MeasureName=WriteThroughput&Namespace=AWS%2FRDS&Period=300&SignatureVersion=1&StartTime=2010-07-02T13%3A02%3A38%2B00%3A00&Statistics.member.1=Average&Timestamp=2010-07-02T13%3A07%3A46Z&Version=2009-05-15&Signature=te%2BFObfhYtw8mupe2VnyIZH%2Bmao%3D
# response:
# #<Net::HTTPOK:0x10241f480>
# <GetMetricStatisticsResponse xmlns="http://monitoring.amazonaws.com/doc/2009-05-15/">
#   <GetMetricStatisticsResult>
#     <Datapoints>
#       <member>
#         <Timestamp>2010-07-02T13:02:00Z</Timestamp>
#         <Unit>Bytes/Second</Unit>
#         <Samples>5.0</Samples>
#         <Average>1195265.5437945272</Average>
#       </member>
#     </Datapoints>
#     <Label>WriteThroughput</Label>
#   </GetMetricStatisticsResult>
#   <ResponseMetadata>
#     <RequestId>ceded9a9-85da-11df-a662-69fbdd7a7fe8</RequestId>
#   </ResponseMetadata>
# </GetMetricStatisticsResponse>
# 
# {"Action"=>"GetMetricStatistics", "Dimensions.member.1.Value"=>"rp-tracking-service", "Version"=>"2009-05-15", "MeasureName"=>"ReadThroughput", "AWSAccessKeyId"=>"0B5MN90FYXXKWR8S17G2", "Period"=>"300", "SignatureVersion"=>"1", "Timestamp"=>"2010-07-02T13:07:45Z", "Namespace"=>"AWS/RDS", "StartTime"=>"2010-07-02T13:02:38+00:00", "Dimensions.member.1.Name"=>"DBInstanceIdentifier", "Statistics.member.1"=>"Average", "EndTime"=>"2010-07-02T13:07:38+00:00"}
# params:
# nil
# request address : https://monitoring.amazonaws.com:443/?AWSAccessKeyId=0B5MN90FYXXKWR8S17G2&Action=GetMetricStatistics&Dimensions.member.1.Name=DBInstanceIdentifier&Dimensions.member.1.Value=rp-tracking-service&EndTime=2010-07-02T13%3A07%3A38%2B00%3A00&MeasureName=ReadThroughput&Namespace=AWS%2FRDS&Period=300&SignatureVersion=1&StartTime=2010-07-02T13%3A02%3A38%2B00%3A00&Statistics.member.1=Average&Timestamp=2010-07-02T13%3A07%3A45Z&Version=2009-05-15&Signature=mKdDIzxk8XOlNbhmQL9%2BvcFqcJc%3D
# response:
# #<Net::HTTPOK:0x1024321e8>
# <GetMetricStatisticsResponse xmlns="http://monitoring.amazonaws.com/doc/2009-05-15/">
#   <GetMetricStatisticsResult>
#     <Datapoints>
#       <member>
#         <Timestamp>2010-07-02T13:02:00Z</Timestamp>
#         <Unit>Bytes/Second</Unit>
#         <Samples>5.0</Samples>
#         <Average>299045.0018647535</Average>
#       </member>
#     </Datapoints>
#     <Label>ReadThroughput</Label>
#   </GetMetricStatisticsResult>
#   <ResponseMetadata>
#     <RequestId>ce765366-85da-11df-b0b9-0fe5cd074bc5</RequestId>
#   </ResponseMetadata>
# </GetMetricStatisticsResponse>
# 
# 
# 
# 
# 
