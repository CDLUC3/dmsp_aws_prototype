# rubocop:disable Naming/FileName
# frozen_string_literal: true

require 'json'

require 'uc3-dmp-cognito'
require 'uc3-dmp-dynamo'

require 'uc3-dmp-provenance/finder'
require 'uc3-dmp-provenance/helper'

# Entrypoint for the uc3-dmp-provenance gem
module Uc3DmpProvenance
  MSG_PROVENANCE_NOT_FOUND = 'Provenance does not exist.'
end
# rubocop:enable Naming/FileName
