# frozen_string_literal: true

require 'aws-sdk-sns'
require 'aws-sdk-ssm'

require 'uc3-dmp-api-core/notifier'
require 'uc3-dmp-api-core/paginator'
require 'uc3-dmp-api-core/responder'
require 'uc3-dmp-api-core/ssm_reader'

module Uc3DmpApiCore
  # General HTTP Response Messages
  # ----------------------------------------
  MSG_SUCCESS = 'Success'
  MSG_INVALID_ARGS = 'Invalid arguments.' # For HTTP 400 (Bad request)
  MSG_SERVER_ERROR = 'Unable to process your request at this time.' # For HTTP 500 (Server error)
end
