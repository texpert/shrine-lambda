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
          raise Error, "The :#{key} is required for Lambda plugin" if value == :required && uploader.opts[key].nil?
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
        # @param (see Aws::Lambda::Client#initialize)
        def lambda(access_key_id:     opts[:access_key_id],
                   secret_access_key: opts[:secret_access_key],
                   region:            opts[:region], **args)

          Aws::Lambda::Client.new(args.merge!(access_key_id:     access_key_id,
                                              secret_access_key: secret_access_key,
                                              region:            region))
        end

        # Memoize and returns a list of your Lambda functions. For each function, the
        # response includes the function configuration information.
        #
        # @param (see Aws::Lambda::Client#list_functions)
        # @param force [Boolean] reloading the list via request to AWS if true
        def lambda_function_list(master_region: nil, function_version: 'ALL', marker: nil, items: 100, force: false)
          fl = opts[:lambda_function_list]
          return fl unless force || fl.nil? || fl.empty?
          opts[:lambda_function_list] = lambda.list_functions(master_region: master_region,
                                                              function_version: function_version,
                                                              marker: marker,
                                                              max_items: items)
        end
      end

      module InstanceMethods
        # A cached instance of an AWS Lambda client.
        def lambda
          @lambda ||= self.class.lambda
        end

        def lambda_function_list(force: false)
          fl = opts[:lambda_function_list]
          return fl unless force || fl.nil? || fl.empty?
          self.class.lambda_function_list(force: force)
        end
      end
    end

    register_plugin(:lambda, Lambda)
  end
end
