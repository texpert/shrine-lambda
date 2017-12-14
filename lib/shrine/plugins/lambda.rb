# frozen_string_literal: true

require 'aws-sdk-lambda'

class Shrine
  module Plugins
    module Lambda
      # Required AWS credentials:
      REQUIRED = %i[access_key_id region secret_access_key].freeze

      Error = Class.new(Shrine::Error)

      # If promoting was not yet overridden, it is set to automatically trigger
      # Lambda processing defined in `Shrine#lambda_process`.
      def self.configure(uploader, settings = {})
        REQUIRED.each do |option|
          uploader.opts[option] = settings.fetch(option, uploader.opts[option])
          raise Error, "The :#{option} is required for Lambda plugin" if uploader.opts[option].nil?
        end

        # TODO: Check this - seems it have to be a requirement, not an option
        uploader.opts[:backgrounding_promote] ||= proc { lambda_process }
      end

      # It loads the backgrounding plugin, so that it can override promoting.
      # TODO: Check if versioning plugin should be a required dependency
      def self.load_dependencies(uploader, _opts = {})
        uploader.plugin :backgrounding
      end
    end

    register_plugin(:lambda, Lambda)
  end
end
