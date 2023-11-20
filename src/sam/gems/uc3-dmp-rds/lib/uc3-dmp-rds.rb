# rubocop:disable Naming/FileName
# frozen_string_literal: true

require 'uc3-dmp-rds/adapter'
require 'uc3-dmp-rds/authenticator'

# RDS Database adapter
module Uc3DmpRds
  MSG_MISSING_TOKEN = 'Missing API Token. Expected header: `Authorization: token 12345`'
  MSG_MISSING_USER = 'Unknown or unauthenticated user'
end
# rubocop:enable Naming/FileName
