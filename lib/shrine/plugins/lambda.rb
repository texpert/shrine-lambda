# frozen_string_literal: true

require 'aws-sdk-lambda'

class Shrine
  module Plugins
    module Lambda
      # Required AWS credentials:
      SETTINGS = { access_key_id: :required, region: :required, callback_url: :optional,
                   secret_access_key: :required }

      Error = Class.new(Shrine::Error)

      # If promoting was not yet overridden, it is set to automatically trigger
      # Lambda processing defined in `Shrine#lambda_process`.
      def self.configure(uploader, settings = {})
        settings.each do |option|
          uploader.opts[option] = settings.fetch(option, uploader.opts[option])
          if SETTINGS[option] == :required && uploader.opts[option].nil?
            raise Error, "The :#{option} is required for Lambda plugin"
          end
        end

        # TODO: Check this - seems it have to be a requirement, not an option
        uploader.opts[:backgrounding_promote] ||= proc { lambda_process }
      end

      # It loads the backgrounding plugin, so that it can override promoting.
      def self.load_dependencies(uploader, _opts = {})
        uploader.plugin :backgrounding
      end
    end

    register_plugin(:lambda, Lambda)
  end
end
