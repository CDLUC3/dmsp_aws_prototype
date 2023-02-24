# frozen_string_literal: true

# ----------------------------------------
# Potential messages returned to Lambdas
# ----------------------------------------
# Standard error messages
class Messages
  # DMP
  # ----------------------------------------
  MSG_DMP_EXISTS = 'DMP already exists. Try :update instead.'
  MSG_DMP_UNKNOWN = 'DMP does not exist. Try :create instead.'
  MSG_DMP_NOT_FOUND = 'DMP does not exist.'
  MSG_DMP_FORBIDDEN = 'You do not have permission.'
  MSG_DMP_NO_DMP_ID = 'A DMP ID could not be registered at this time.'
  MSG_DMP_INVALID_DMP_ID = 'Invalid DMP ID format.'
  MSG_DMP_NO_HISTORICALS = 'You cannot modify a historical version of the DMP.'
  MSG_DMP_UNABLE_TO_VERSION = 'Unable to version this DMP.'

  # Provenanace
  # ----------------------------------------
  MSG_PROVENANCE_NOT_FOUND = 'Provenance does not exist.'

  # JSON Validation
  # ----------------------------------------
  MSG_EMPTY_JSON = 'JSON was empty or was not a valid JSON document!'
  MSG_INVALID_JSON = 'Invalid JSON.'
  MSG_NO_SCHEMA = 'No JSON schema available!'
  MSG_BAD_JSON = 'Fatal validation error: %{msg}'
  MSG_VALID_JSON = 'The JSON is valid.'

  # General
  # ----------------------------------------
  MSG_SUCCESS = 'Success'
  MSG_SERVER_ERROR = 'Unable to process your request at this time.' # For HTTP 500 (Server error)
  MSG_INVALID_ARGS = 'Invalid arguments.' # For HTTP 400 (Bad request)

  # External services
  # ----------------------------------------
  MSG_EZID_FAILURE = 'Unable to publish changes with EZID.'
  MSG_S3_FAILURE = 'Unable to write to the S3 Bucket.'
  MSG_DOWNLOAD_FAILURE = 'Unable to download the DMP document.'
end
