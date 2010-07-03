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

    LABELS.each do |label, unit|
      next if label == 'StorageSpace'
      
      @random_label_values[label] = random_value = Kernel.rand(1000000)*0.1
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

    @random_label_values['StorageSpace'] = random_value = Kernel.rand(1000).to_f
    FakeWeb.register_uri(:post, %r|https://rds.amazonaws.com/|, :body => <<-EOF)
    #<Net::HTTPOK:0x101897cc0>
<DescribeDBInstancesResponse xmlns="http://rds.amazonaws.com/admin/2009-10-16/">
  <DescribeDBInstancesResult>
    <DBInstances>
      <DBInstance>
        <LatestRestorableTime>2010-07-03T13:15:01Z</LatestRestorableTime>
        <Engine>mysql5.1</Engine>
        <PendingModifiedValues/>
        <BackupRetentionPeriod>7</BackupRetentionPeriod>
        <DBInstanceStatus>available</DBInstanceStatus>
        <DBParameterGroups>
          <DBParameterGroup>
            <ParameterApplyStatus>in-sync</ParameterApplyStatus>
            <DBParameterGroupName>rp-tracking-service</DBParameterGroupName>
          </DBParameterGroup>
        </DBParameterGroups>
        <DBInstanceIdentifier>rp-tracking-service</DBInstanceIdentifier>
        <Endpoint>
          <Port>3306</Port>
          <Address>rp-tracking-service.chuf4accixkx.us-east-1.rds.amazonaws.com</Address>
        </Endpoint>
        <DBSecurityGroups>
          <DBSecurityGroup>
            <Status>active</Status>
            <DBSecurityGroupName>default</DBSecurityGroupName>
          </DBSecurityGroup>
        </DBSecurityGroups>
        <PreferredBackupWindow>03:00-05:00</PreferredBackupWindow>
        <PreferredMaintenanceWindow>sat:07:00-sat:11:00</PreferredMaintenanceWindow>
        <AvailabilityZone>us-east-1c</AvailabilityZone>
        <InstanceCreateTime>2009-11-10T14:29:40.700Z</InstanceCreateTime>
        <AllocatedStorage>#{random_value}</AllocatedStorage>
        <DBInstanceClass>db.m1.large</DBInstanceClass>
        <MasterUsername>root</MasterUsername>
      </DBInstance>
    </DBInstances>
  </DescribeDBInstancesResult>
  <ResponseMetadata>
    <RequestId>4a538f00-86a5-11df-a855-6f7e7a5a1fd9</RequestId>
  </ResponseMetadata>
</DescribeDBInstancesResponse>
EOF

  
    plugin.build_report
    @report_hash = plugin.data_for_server[:reports].inject({}){|r,d|r.merge!(d)}
    
  end
  
  (LABELS.keys - ["FreeStorageSpace"]).each do |label| 
    it "should receive the right value for #{label}" do
      @report_hash[label].class.should == @random_label_values[label].class
      @report_hash[label].to_s.should == @random_label_values[label].to_s
    end    
  end

  it "should receive the right value for Storage**" do
    free_storage_space = @random_label_values["FreeStorageSpace"]
    free_storage_space = ((free_storage_space.to_f / (1024 * 1024 * 1024))*100).floor / 100
    storage_space      = @random_label_values["StorageSpace"]
    used_storage_space = storage_space - free_storage_space


    @report_hash["StorageSpace"].should          == storage_space
    @report_hash["FreeStorageSpace"].should      == free_storage_space
    @report_hash["UsedStorageSpace"].should      == used_storage_space
    @report_hash["StorageSpace capacity"].should == (used_storage_space / storage_space * 100)
  end    
  
  
end
