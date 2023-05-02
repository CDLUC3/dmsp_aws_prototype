# frozen_string_literal: true

require 'ostruct'

def mock_active_record_base(success: true)
  allow(ActiveRecord::Base).to receive(:establish_connection).and_return(success)
  allow(ActiveRecord::Base).to receive(:connected?).and_return(success)
  allow(ActiveRecord::Base).to receive(:simple_execute).and_return(success ? %w[foo bar] : [])
end

def aws_error(msg: 'Testing')
  Aws::Errors::ServiceError.new(Seahorse::Client::RequestContext.new, msg)
end
