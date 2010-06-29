class NumFiles < Scout::Plugin
  needs 'csv'
  
  OPTIONS=<<-EOS
    username:
      name: AWS Username
      notes: Email address for your AWS account
    password:
      name: AWS Password
    buckets:
      name: S3 Buckets
      notes: Comma-separated list. Leave empty for all buckets.
      default:
    script_path:
      name: Script path
      notes: Path to check_aws_usage.py
      default: check_aws_usage.py
  EOS
  
  FIELDS = {
    # outputField => [Operation match, UsageType match, unit conversion]
    
    # storage
    'storage' => [//, /TimedStorage-ByteHrs/, :byteHours],
    'storage_count' => [//, /StorageObjectCount/],
    
    # requests
    # we ignore createbucket/deletebucket/listallmybucket requests
    'req_list' => [/ListBucket/, /Requests-/],
    'req_head' => [/HeadObject/, /Requests-/],
    'req_get' => [/GetObject/, /Requests-/],
    'req_put' => [/PutObject/, /Requests-/],
    'req_delete' => [/DeleteObject/, /Requests-/],
    'req_copy' => [/CopyObject/, /Requests-/],

    # data-transfer
    'data_aws' => [//, /C3DataTransfer-(In)|(Out)-Bytes/, :bytes],
    'data_in' => [//, /^DataTransfer-In-Bytes/, :bytes],
    'data_out' => [//, /^DataTransfer-Out-Bytes/, :bytes],
    
    # we also ignore logging (ReadACL/PutObject, NoCharge/LogServiceDataTransfer-*-Bytes)
  }
  
  def build_report
    date_val = Time.now.utc 
    date_from = date_val.strftime('%Y-%m-%d')
    date_to = (date_val + (60*60*24)).strftime('%Y-%m-%d') 
    
    # download the data from AWS
    csv_report = `#{option(:script_path)} --period hours --username "#{option(:username)}" --password "#{option(:password)}" --service "AmazonS3" #{date_from} #{date_to}`
    if $?.exitstatus != 0
      # re-run and capture stderr this time
      output = `#{option(:script_path)} --period hours --username "#{option(:username)}" --password "#{option(:password)}" --service "AmazonS3" #{date_from} #{date_to} 2>&1`
      return errors << {:subject => "Unable to retrieve report data from Amazon.",
                        :body => "Exit code: #{$?.exitstatus}\n#{output}"}
    end
    # comment out the above, and uncomment below to do some local testing...
    #csv_report = File.new('/path/to/test_data.csv', 'rb').read
    
    # parse the CSV data into a [{key:value, ...}, ...] structure
    csv_data = CSV.parse csv_report
    headers = csv_data.shift.map {|i| i.to_s.strip }
    string_data = csv_data.map {|row| row.map {|cell| cell.to_s } }
    report_data = string_data.map {|row| Hash[*headers.zip(row).flatten] }    
    
    # filter the data based on buckets option
    if ! (option(:buckets).nil? or option(:buckets).empty?)
      buckets = option(:buckets).split(/, */)
      # filter it
      report_data.reject! {|x| ! buckets.include?(x['Resource']) } 
    end

    # filter based on dates
    # keep the last ByteHrs data and the last hour of everything else
    report_data.reverse!
    last_date = nil
    byte_hrs_date = nil
    report_data.each_index do |i|
      report_row = report_data[i]
      if report_row['UsageType'].nil?
        # drop empty rows
        report_data.delete_at(i)
      elsif report_row['UsageType'].include?('-ByteHrs')
        # bytehours stuff only gets reported every 12h or so
        if byte_hrs_date.nil?
          byte_hrs_date = report_row['EndTime']
        elsif report_row['EndTime'] != byte_hrs_date
          report_data.delete_at(i)
        end
      else
        # everything else gets reported per-hour
        if last_date.nil?
          last_date = report_row['EndTime']
        elsif report_row['EndTime'] != last_date
          report_data.delete_at(i)
        end
      end
    end
            
    # Aggregate all the values
    summary = {}
    FIELDS.each do |k,v|
      summary[k] = 0
    end
    for report_row in report_data do
      FIELDS.each do |k,v|
        if report_row['Operation'].match(v[0]) and report_row['UsageType'].match(v[1])
          summary[k] += report_row['UsageValue'].to_i
        end
      end
    end
    
    # Convert any Byte values into GB
    # and ByteHrs into GB (divide by 24 hours)
    summary.each do |k,v|
      if FIELDS[k].at(2) == :byteHours
        summary[k] = v.to_f / (1024*1024*1024) / 24
      elsif FIELDS[k].at(2) == :bytes
        summary[k] = v.to_f / (1024*1024*1024)
      end
    end
    
    report(summary)
  end
end
