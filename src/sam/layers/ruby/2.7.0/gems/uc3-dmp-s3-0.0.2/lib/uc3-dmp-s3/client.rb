# frozen_string_literal: true

require 'aws-sdk-s3'
require 'base64'
require 'cgi'

module Uc3DmpS3
  # Error from the Rds Adapter
  class ClientError < StandardError; end

  # A module to interact with the RDS DB. Expects the following ENV variables to be set:
  #     DATABASE_HOST:  The host URL
  #     DATABASE_PORT:  The port to use
  #     DATABASE_NAME:  The name of the database
  #
  # and the following should be passed into the :connect method:
  #     RDS_USERNAME:   The RDS username
  #     RDS_PASSWORD:   The RDS password
  #
  class Client
    NARRATIVE_KEY_PREFIX = 'narratives/'

    MSG_S3_FAILURE = 'Unable to save the object at this time'

    class << self
      # Put the narrative file into the S3 bucket
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
      def put_narrative(document:, dmp_id: nil, base64: false)
        return nil if !document.is_a?(String) || document.strip.empty? || ENV['S3_BUCKET'].nil?

        key = "#{NARRATIVE_KEY_PREFIX}#{SecureRandom.hex(8)}.pdf"
        tg = dmp_id.nil? ? "PRE-DMP_ID=#{Time.now.strftime('%Y-%m-%d')}" : "DMP_ID=#{CGI.escape(dmp_id)}"
        body = base64 ? Base64.decode64(document) : document

        _put_object(key: key, tags: tg, payload: body)
      rescue Aws::Errors::ServiceError => e
        msg = "Unable to write PDF narrative to S3 bucket (dmp_id: #{dmp_id.nil? ? 'PRE-DMP_ID' : dmp_id})"
        raise ClientError, "#{msg} - #{e.message}"
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

      # Fetch the narrative file from the S3 bucket
      def get_narrative(key:)
        return nil unless key.is_a?(String) && !key.strip.empty? && !ENV['S3_BUCKET'].nil?

        obj = _get_object(key: key.start_with?(NARRATIVE_KEY_PREFIX) ? key : "#{NARRATIVE_KEY_PREFIX}#{key}")
        Base64.encode64(obj)
      rescue Aws::Errors::ServiceError => e
        raise ClientError, "Unable to fetch PDF narrative from S3 bucket (key: #{key}) - #{e.message}"
      end

      private

      # Put the object into the S3 bucket
      def _put_object(key:, payload:, tags: '')
        return nil unless key.is_a?(String) && !key.strip.empty? && !payload.nil? && !ENV['S3_BUCKET'].nil?

        client = Aws::S3::Client.new(region: ENV.fetch('AWS_REGION', nil))
        bucket = ENV['S3_BUCKET'].gsub('arn:aws:s3:::', '')
        resp = client.put_object({ body: payload, bucket: bucket, key: key, tagging: tags })
        resp.successful? ? key : nil
      end

      # Fetch the object from the S3 bucket
      # rubocop:disable Metrics/AbcSize
      def _get_object(key:)
        return nil unless key.is_a?(String) && !key.strip.empty? && !ENV['S3_BUCKET'].nil?

        client = Aws::S3::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        bucket = ENV['S3_BUCKET'].gsub('arn:aws:s3:::', '')
        resp = client.get_object({ bucket: bucket, key: key })
        return nil if resp.nil? || !resp.content_length.positive?

        resp.body.is_a?(String) ? resp.body : resp.body.read
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
