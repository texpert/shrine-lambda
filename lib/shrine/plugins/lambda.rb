# frozen_string_literal: true

require 'aws-sdk-lambda'

class Shrine
  module Plugins
    module Lambda
      SETTINGS = { access_key_id: :required,
                   callback_url: :optional,
                   convert_params: :optional,
                   endpoint: :optional,
                   log_formatter: :optional,
                   log_level: :optional,
                   logger: :optional,
                   profile: :optional,
                   region: :required,
                   retry_limit: :optional,
                   secret_access_key: :required,
                   session_token: :optional,
                   stub_responses: :optional,
                   validate_params: :optional }.freeze

      Error = Class.new(Shrine::Error)

      # If promoting was not yet overridden, it is set to automatically trigger
      # Lambda processing defined in `Shrine#lambda_process`.
      def self.configure(uploader, settings = {})
        settings.each do |key, value|
          raise Error, "The :#{key} is not supported by the Lambda plugin" unless SETTINGS[key]
          uploader.opts[key] = value || uploader.opts[key]
          if SETTINGS[key] == :required && uploader.opts[key].nil?
            raise Error, "The :#{key} is required for Lambda plugin"
          end
        end

        uploader.opts[:backgrounding_promote] ||= proc { lambda_process }
      end

      # It loads the backgrounding plugin, so that it can override promoting.
      def self.load_dependencies(uploader, _opts = {})
        uploader.plugin :backgrounding
      end

      module AttacherClassMethods
        # Loads the attacher from the data, and triggers AWS Lambda
        # processing. Intended to be used in a background job.
        def lambda_process(data)
          attacher = load(data)
          cached_file = attacher.uploaded_file(data['attachment'])
          attacher.lambda_process(cached_file)
          attacher
        end
      end

      module AttacherMethods
        # Triggers AWS Lambda processing defined by the user in
        # `Shrine#lambda_process`. It dumps the attacher in the payload of
        # the request, so that it's included in the webhook and that we know
        # which webhook belongs to which record/attachment.
        #
        # After the AWS Lambda assembly was submitted, the response is saved
        # into cached file's metadata, which can then be reloaded at will for
        # checking progress of the assembly.
        #
        # It raises a `Shrine::Error` if AWS Lambda returned an error.
        def lambda_process(cached_file)
          assembly = store.lambda_process(cached_file, context)
          origin = Shrine.storages[:cache]
          target = Shrine.storages[:store]
          response = Shrine.lambda_client.invoke(function_name: assembly[:function],
                                                 invocation_type: 'RequestResponse',
                                                 log_type: 'Tail',
                                                 payload: { storages: [cache: { name: origin.bucket.name,
                                                                                prefix: origin.prefix },
                                                                       store: { name: target.bucket.name,
                                                                                prefix: target.prefix }],
                                                            path:        store.generate_location(cached_file, context),
                                                            callbackURL: Shrine.opts[:callback_url] }
                                                               .merge(assembly.slice(:original, :versions)).to_json)
          raise Error, "#{response['error']}: #{response['message']}" if response.function_error
          cached_file.metadata['lambda_response'] = response.payload
          swap(cached_file) || _set(cached_file)
        end
      end

      module ClassMethods
        # Creates a new AWS Lambda client
        # @param (see Aws::Lambda::Client#initialize)
        def lambda_client(access_key_id:     opts[:access_key_id],
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
          opts[:lambda_function_list] = lambda_client.list_functions(master_region: master_region,
                                                                     function_version: function_version,
                                                                     marker: marker,
                                                                     max_items: items)
        end
      end

      module InstanceMethods
        # A cached instance of an AWS Lambda client.
        def lambda_client
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
