# rubocop:disable Naming/FileName
# frozen_string_literal: true

require 'json'
require 'json-schema'

require 'uc3-dmp-event-bridge'

require 'uc3-dmp-id/asserter'
require 'uc3-dmp-id/creator'
require 'uc3-dmp-id/deleter'
require 'uc3-dmp-id/finder'
require 'uc3-dmp-id/helper'
require 'uc3-dmp-id/updater'
require 'uc3-dmp-id/validator'
require 'uc3-dmp-id/versioner'

require 'uc3-dmp-id/schemas/amend'
require 'uc3-dmp-id/schemas/author'

module Uc3DmpId
  MSG_DMP_EXISTS = 'DMP already exists. Try :update instead.'
  MSG_DMP_FORBIDDEN = 'You do not have permission.'
  MSG_DMP_INVALID_DMP_ID = 'Invalid DMP ID format.'
  MSG_DMP_NO_DMP_ID = 'A DMP ID could not be registered at this time.'
  MSG_DMP_NO_HISTORICALS = 'You cannot modify a historical version of the DMP.'
  MSG_NO_OWNER_ORG = 'Could not determine ownership of the DMP ID.'
  MSG_DMP_NO_TOMBSTONE = 'Unable to tombstone the DMP ID at this time.'
  MSG_DMP_NO_UPDATE = 'Unable to update the DMP ID at this time.'
  MSG_DMP_NOT_FOUND = 'DMP does not exist.'
  MSG_DMP_UNABLE_TO_VERSION = 'Unable to version this DMP.'
  MSG_DMP_UNKNOWN = 'DMP does not exist. Try :create instead.'
end
# rubocop:enable Naming/FileName
