# frozen_string_literal: true

require 'aws-sdk-cognitoidentityprovider'

module Uc3DmpProvenance
  # Generic helper methods meant for use by the other classes in this gem.
  class Helper
    PK_PROVENANCE_PREFIX = 'PROVENANCE#'
    SK_PROVENANCE_PREFIX = 'PROFILE'

    DOI_REGEX = %r{[0-9]{2}\.[0-9]{5}/[a-zA-Z0-9/_.-]+}
    URL_REGEX = %r{(https?://)?([a-zA-Z0-9\-_]\.)+[a-zA-Z0-9\-_]{2,3}(:[0-9]+)?/?}

    class << self
      # Append the PK prefix for the object
      # -------------------------------------------------------------------------------------
      def append_pk_prefix(provenance:)
        provenance.is_a?(String) ? "#{PK_PROVENANCE_PREFIX}#{remove_pk_prefix(provenance:)}" : nil
      end

      # Strip off the PK prefix
      # -------------------------------------------------------------------------------------
      def remove_pk_prefix(provenance:)
        provenance.is_a?(String) ? provenance.gsub(PK_PROVENANCE_PREFIX, '') : provenance
      end

      # Appends the Provenance system's identifier to the value
      #   For a DOI, it will return the DOI as-is
      #
      #   For a :provenance whose PK is 'PROVENANCE#example' and homepage is 'https://example.com' and
      #   callbackUri is 'https://example.com/callback':
      #     when the :value is '12345', it will return 'example#12345'
      #     when the :value is 'https://example.com/dmps/12345', it will return 'example#dmp/12345'
      #     when the :value is 'https://example.com/callback/12345' it will return 'example#12345'
      #
      # rubocop:disable Metrics/AbcSize
      def format_provenance_callback_url(provenance:, value:)
        # return it as-is if there is no provenance or it's already a URL
        return value if provenance.nil? || provenance.fetch('callbackUri', provenance['homepage']).nil?

        # return it as-is if it's a DOI
        doi = value.match(DOI_REGEX).to_s
        return value unless doi.nil? || doi == '' || !value.start_with?('http')

        # Remove the homepage or callbackUri because we will add this when needed. we just want the id
        val = value.downcase
                   .gsub(provenance.fetch('callbackUri', '').downcase, '')
                   .gsub(provenance.fetch('homepage', '').downcase, '')
        val = val.gsub(%r{https?://}, '')
        val = val[1..val.length] if val.start_with?('/')
        id = provenance['PK']&.gsub(PK_PROVENANCE_PREFIX, '')
        id.nil? ? val : "#{id}##{val}"
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
