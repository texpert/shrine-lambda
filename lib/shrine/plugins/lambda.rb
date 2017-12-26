# frozen_string_literal: true

require 'aws-sdk-lambda'

class Shrine
  module Plugins
    module Lambda
      SETTINGS = { access_key_id: :required, callback_url: :optional, region: :required,
                   secret_access_key: :required }.freeze

      Error = Class.new(Shrine::Error)

      # If promoting was not yet overridden, it is set to automatically trigger
      # Lambda processing defined in `Shrine#lambda_process`.
      def self.configure(uploader, settings = {})
        SETTINGS.each_key do |key, value|
          uploader.opts[key] = settings.fetch(key, uploader.opts[key])
          if value == :required && uploader.opts[key].nil?
            raise Error, "The :#{key} is required for Lambda plugin"
          end
        end

        # TODO: Check this - seems it have to be a requirement, not an option
        uploader.opts[:backgrounding_promote] ||= proc { lambda_process }
      end

      # It loads the backgrounding plugin, so that it can override promoting.
      def self.load_dependencies(uploader, _opts = {})
        uploader.plugin :backgrounding
      end

      module ClassMethods
        # Creates a new AWS Lambda client
        def lambda
          Aws::Lambda::Client.new(access_key_id:     opts[:access_key_id],
                                  secret_access_key: opts[:secret_access_key],
                                  region:            opts[:region])
        end

        def lambda_function_list()
          opts[:lambda_function_list] = lambda.list_functions(# master_region: s3_options[:region],
                                                              function_version: 'ALL', # accepts ALL
                                                              # marker: 'String',
                                                              max_items: 100)
        end
      end

      module InstanceMethods
        # A cached instance of an AWS Lambda client.
        def lambda
          @lambda ||= self.class.lambda
        end

        def lambda_function_list(force: false)
          fl = self.opts[:lambda_function_list]
          return fl unless force || fl.nil? || fl.empty?
          self.class.lambda_function_list
          self.opts[:lambda_function_list]
        end
      end
    end

    register_plugin(:lambda, Lambda)
  end
end
