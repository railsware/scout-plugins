require File.dirname(__FILE__) + '/../spec/spec_helper'
require File.dirname(__FILE__) + '/aws_cloudwatch'
require 'fakeweb'

RDS_LABELS = {
    "CPUUtilization" => "Percent",
    "DatabaseConnections" => "Count",
    "ReadIOPS" => "Count/Second",
    "WriteIOPS" => "Count/Second",
    "ReadLatency" => "Seconds",
    "WriteLatency" => "Seconds",
    "ReadThroughput" => "Bytes/Second",
    "WriteThroughput" => "Bytes/Second"
    }

MONITOR_RESPONSE='%Q|<GetMetricStatisticsResponse xmlns="http://monitoring.amazonaws.com/doc/2009-05-15/">
  <GetMetricStatisticsResult>
    <Datapoints>
      <member>
        <Timestamp>#{Time.now.strftime("%Y-%m-%dT%H:%M:%SZ")}</Timestamp>
        <Unit>Abstract Units</Unit>
        <Samples>5.0</Samples>
        <Average>#{average_value}</Average>
      </member>
    </Datapoints>
    <Label>#{label}</Label>
  </GetMetricStatisticsResult>
  <ResponseMetadata>
    <RequestId>ceded9a9-85da-11df-a662-69fbdd7a7fe8</RequestId>
  </ResponseMetadata>
</GetMetricStatisticsResponse>|'

BROKEN_MONITOR_RESPONSE='%Q|<GetMetricStatisticsResponse xmlns="http://monitoring.amazonaws.com/doc/2009-05-15/">
  <GetMetricStatisticsResult>
    <Datapoints/>
    <Label>#{label}</Label>
  </GetMetricStatisticsResult>
  <ResponseMetadata>
    <RequestId>ceded9a9-85da-11df-a662-69fbdd7a7fe8</RequestId>
  </ResponseMetadata>
</GetMetricStatisticsResponse>|'

ERROR_MONITOR_RESPONSE='%Q|<ErrorResponse xmlns="http://monitoring.amazonaws.com/doc/2009-05-15/">
  <Error>
    <Type>Receiver</Type>
    <Code>InternalServiceError</Code>
    <Message>An internal error has occurred.</Message>
  </Error>
  <RequestId>e034f65e-8743-11df-96a0-998bae75c552</RequestId>
</ErrorResponse>|'

RDS_RESPONSE='%Q|<DescribeDBInstancesResponse xmlns="http://rds.amazonaws.com/admin/2009-10-16/">
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
        <AllocatedStorage>#{average_value}</AllocatedStorage>
        <DBInstanceClass>db.m1.large</DBInstanceClass>
        <MasterUsername>root</MasterUsername>
      </DBInstance>
    </DBInstances>
  </DescribeDBInstancesResult>
  <ResponseMetadata>
    <RequestId>4a538f00-86a5-11df-a855-6f7e7a5a1fd9</RequestId>
  </ResponseMetadata>
</DescribeDBInstancesResponse>|'

describe "AwsCloudwatch - Usual RDS execution " do
  # it "should run for RDS" do
  before(:all) do
    current_run = Time.now
    last_run = current_run - 3*60
    memory   = {}
    options  = {:aws_access_key => '0B5MN90FYXXKWR8S17G2', :aws_secret =>  '80dRHe6NSdBdt/Tz0P6qrSg6XgM2KKMkFxT4bUzK', :dimension => 'rp-tracking-service',:namespace => 'AWS/RDS'}

    plugin = AwsCloudwatch.new(last_run, memory, options)

    @random_label_values = {}

    FakeWeb.allow_net_connect = false

    AwsCloudwatch::RDS_MEASURES.each do |label|
      # eval options label and average_value
      @random_label_values[label] = average_value = Kernel.rand(100000*10)*0.1
      FakeWeb.register_uri(:get, %r|https://monitoring\.amazonaws\.com.*?MeasureName=#{label}&Namespace=AWS%2FRDS|, :body => eval(MONITOR_RESPONSE))
    end

    # special value for RDS
    label = 'StorageSpace'
    @random_label_values[label] = average_value = storage_space = Kernel.rand(1000).to_f
    FakeWeb.register_uri(:post, %r|https://rds.amazonaws.com/|, :body => eval(RDS_RESPONSE))
    
    @random_label_values["StorageSpace capacity"] = used_capacity = (Kernel.rand*100*100).floor*0.01

    label = 'FreeStorageSpace'
    @random_label_values[label] = average_value = ( (100-used_capacity) / 100 * storage_space * 1024 * 1024 * 1024 ).floor
    FakeWeb.register_uri(:get, %r|https://monitoring\.amazonaws\.com.*?MeasureName=#{label}&Namespace=AWS%2FRDS|, :body => eval(MONITOR_RESPONSE))

    plugin.build_report
    @report_hash = plugin.data_for_server[:reports].inject({}){|r,d|r.merge!(d)}
  end
  
  AwsCloudwatch::RDS_MEASURES.each do |label| 
    it "should receive the right value for #{label}" do
      @report_hash[label].class.should == @random_label_values[label].class
      @report_hash[label].to_s.should == @random_label_values[label].to_s

      @report_hash.delete(label)
    end    
  end

  it "should receive the right value for Storage**" do
    free_storage_space = @random_label_values["FreeStorageSpace"]
    storage_space      = @random_label_values["StorageSpace"].to_f * 1024 * 1024 * 1024
    used_storage_space = storage_space - free_storage_space

    @report_hash["StorageSpace"].should          == storage_space
    @report_hash["FreeStorageSpace"].should      == free_storage_space
    @report_hash["UsedStorageSpace"].should      == used_storage_space
    @report_hash["StorageSpace capacity"].should == @random_label_values["StorageSpace capacity"]
    used_storage_space.should < storage_space

    ["StorageSpace", "FreeStorageSpace", "UsedStorageSpace", "StorageSpace capacity"].each{|k|@report_hash.delete(k)}
  end
  
  it "should be no other keys" do
    @report_hash.empty?.should == true
  end    
  
end

describe "AwsCloudwatch - RDS execution with empty result or error" do
  @success_monitor_response_labels, @broken_monitor_response_labels, @error_monitor_response_labels = [], [], []
  
  before(:all) do
    current_run = Time.now
    last_run = current_run - 3*60
    memory   = {}
    options  = {:aws_access_key => '0B5MN90FYXXKWR8S17G2', :aws_secret =>  '80dRHe6NSdBdt/Tz0P6qrSg6XgM2KKMkFxT4bUzK', :dimension => 'rp-tracking-service',:namespace => 'AWS/RDS'}

    plugin = AwsCloudwatch.new(last_run, memory, options)

    @random_label_values = {}
    @success_monitor_response_labels, @broken_monitor_response_labels, @error_monitor_response_labels = [], [], []
    # eval options label and average_value
    average_value = 1

    FakeWeb.allow_net_connect = false

    AwsCloudwatch::RDS_MEASURES.each do |label|
      # generate 3 random responses
      fake_web_options=[]
      3.times do 
        response = [MONITOR_RESPONSE, BROKEN_MONITOR_RESPONSE, ERROR_MONITOR_RESPONSE][Kernel.rand(3)]

        fake_web_options << options={:times => 1, :body => eval(response)}

        case response
        when MONITOR_RESPONSE
          @broken_monitor_response_labels.delete(label)
          @error_monitor_response_labels.delete(label)
          @success_monitor_response_labels << MONITOR_RESPONSE
          break # there will be no more issues after succes response
        when BROKEN_MONITOR_RESPONSE
          @broken_monitor_response_labels << label
          @error_monitor_response_labels.delete(label)
        when ERROR_MONITOR_RESPONSE
          options[:status] = ["504", "Internal Server Error"] if response == ERROR_MONITOR_RESPONSE
          @broken_monitor_response_labels.delete(label)
          @error_monitor_response_labels << label
        end  
      end
      
      FakeWeb.register_uri(:get, %r|https://monitoring\.amazonaws\.com.*?MeasureName=#{label}&Namespace=AWS%2FRDS|, fake_web_options)
    end

    average_value = 1
    FakeWeb.register_uri(:post, %r|https://rds.amazonaws.com/|, :body => eval(RDS_RESPONSE))

    plugin.build_report
    
    @error_hash = plugin.data_for_server[:errors].inject({}) do |r,error|
      r[error[:body].split("\n").first] = true
      r
    end
    
    @report_hash = plugin.data_for_server[:reports].inject({}){|r,d|r.merge!(d)}
  end

  AwsCloudwatch::RDS_MEASURES.each do |label| 
    it "should render a correct result on label : #{label}" do
      if @success_monitor_response_labels.include?(label)
        @report_hash[label].should == 1
      elsif @broken_monitor_response_labels.include?(label)
        @error_hash["Something went wrong with AWS getMetricStatistics for label #{label}"].should == true
      elsif @error_monitor_response_labels.include?(label)
        @error_hash["Got AWS getMetricStatistic error for measure #{label}"].should == true
      end
    end
  end

end

describe "AwsCloudwatch - Usual EC2 execution " do
  before(:all) do
    current_run = Time.now
    last_run = current_run - 3*60
    memory   = {}
    options  = {:aws_access_key => '0B5MN90FYXXKWR8S17G2', :aws_secret =>  '80dRHe6NSdBdt/Tz0P6qrSg6XgM2KKMkFxT4bUzK', :dimension => 'rp-tracking-service',:namespace => 'AWS/EC2'}

    plugin = AwsCloudwatch.new(last_run, memory, options)

    @random_label_values = {}

    FakeWeb.allow_net_connect = false

    AwsCloudwatch::EC2_MEASURES.each do |label|
      # eval options label and average_value
      @random_label_values[label] = average_value = Kernel.rand(100000*10)*0.1
      FakeWeb.register_uri(:get, %r|https://monitoring\.amazonaws\.com.*?MeasureName=#{label}&Namespace=AWS%2FEC2|, :body => eval(MONITOR_RESPONSE))
    end

    plugin.build_report
    @report_hash = plugin.data_for_server[:reports].inject({}){|r,d|r.merge!(d)}
  end
  
  AwsCloudwatch::EC2_MEASURES.each do |label| 
    it "should receive the right value for #{label}" do
      @report_hash[label].class.should == @random_label_values[label].class
      @report_hash[label].to_s.should == @random_label_values[label].to_s

      @report_hash.delete(label)
    end    
  end

  it "should be no other keys" do
    @report_hash.empty?.should == true
  end    
  
end


describe "AwsCloudwatch - EC2 execution with empty result or error" do
  @success_monitor_response_labels, @broken_monitor_response_labels, @error_monitor_response_labels = [], [], []
  
  before(:all) do
    current_run = Time.now
    last_run = current_run - 3*60
    memory   = {}
    options  = {:aws_access_key => '0B5MN90FYXXKWR8S17G2', :aws_secret =>  '80dRHe6NSdBdt/Tz0P6qrSg6XgM2KKMkFxT4bUzK', :dimension => 'rp-tracking-service',:namespace => 'AWS/EC2'}

    plugin = AwsCloudwatch.new(last_run, memory, options)

    @random_label_values = {}
    @success_monitor_response_labels, @broken_monitor_response_labels, @error_monitor_response_labels = [], [], []
    # eval options label and average_value
    average_value = 1

    FakeWeb.allow_net_connect = false

    AwsCloudwatch::EC2_MEASURES.each do |label|
      # generate 3 random responses
      fake_web_options=[]
      3.times do 
        response = [MONITOR_RESPONSE, BROKEN_MONITOR_RESPONSE, ERROR_MONITOR_RESPONSE][Kernel.rand(3)]

        fake_web_options << options={:times => 1, :body => eval(response)}

        case response
        when MONITOR_RESPONSE
          @broken_monitor_response_labels.delete(label)
          @error_monitor_response_labels.delete(label)
          @success_monitor_response_labels << MONITOR_RESPONSE
          break # there will be no more issues after succes response
        when BROKEN_MONITOR_RESPONSE
          @broken_monitor_response_labels << label
          @error_monitor_response_labels.delete(label)
        when ERROR_MONITOR_RESPONSE
          options[:status] = ["504", "Internal Server Error"] if response == ERROR_MONITOR_RESPONSE
          @broken_monitor_response_labels.delete(label)
          @error_monitor_response_labels << label
        end  
      end
      
      FakeWeb.register_uri(:get, %r|https://monitoring\.amazonaws\.com.*?MeasureName=#{label}&Namespace=AWS%2FEC2|, fake_web_options)
    end

    plugin.build_report
    
    @error_hash = plugin.data_for_server[:errors].inject({}) do |r,error|
      r[error[:body].split("\n").first] = true
      r
    end
    
    @report_hash = plugin.data_for_server[:reports].inject({}){|r,d|r.merge!(d)}
  end

  AwsCloudwatch::EC2_MEASURES.each do |label| 
    it "should render a correct result on label : #{label}" do
      if @success_monitor_response_labels.include?(label)
        @report_hash[label].should == 1
      elsif @broken_monitor_response_labels.include?(label)
        @error_hash["Something went wrong with AWS getMetricStatistics for label #{label}"].should == true
      elsif @error_monitor_response_labels.include?(label)
        @error_hash["Got AWS getMetricStatistic error for measure #{label}"].should == true
      end
    end
  end
  

end
