require 'rubygems'
require 'activeresource'

class HoptoadStats < Scout::Plugin
#  needs 'activeresource'

  def build_report

    Error.site = "http://#{option('account')}.hoptoadapp.com"
    Error.api_token = option('api_token')

    page = 1
    num_errors = 0
    num_notices = 0
    more_errors = true

    while more_errors do
      errors = Error.find :all, :params => { :page => page }

      if errors.size > 0
        num_errors += errors.size
        errors.each do |e|
          num_notices += e.notices_count
        end
        page += 1
      else
          more_errors = false
      end
    end

    report(:errors => num_errors, :notices => num_notices)
  rescue
    error( :subject => "Error talking to hoptoad or parsing xml", :body => $!.message)
  end

end

class Error<ActiveResource::Base

  @api_token = ""

  def self.api_token=(api_token)
    @api_token = api_token
  end

  def self.find(*arguments)
      arguments = append_auth_token_to_params(*arguments)
      super(*arguments)
  end

  def self.append_auth_token_to_params(*arguments)
    opts = arguments.last.is_a?(Hash) ? arguments.pop : {}
    opts = opts.has_key?(:params) ? opts : opts.merge(:params => {}) 
    opts[:params] = opts[:params].merge(:auth_token => @api_token)
    arguments << opts
    arguments
  end
end