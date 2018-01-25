# frozen_string_literal: true

require 'aws-sdk-lambda'

class Shrine
  module Plugins
    module Lambda
      SETTINGS = { access_key_id: :optional,
                   buckets: :required,
                   callback_url: :optional,
                   convert_params: :optional,
                   endpoint: :optional,
                   log_formatter: :optional,
                   log_level: :optional,
                   logger: :optional,
                   profile: :optional,
                   region: :required,
                   retry_limit: :optional,
                   secret_access_key: :optional,
                   session_token: :optional,
                   stub_responses: :optional,
                   target_storage: :required,
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
        # Loads the attacher from the data, and triggers its instance AWS Lambda
        # processing method. Intended to be used in a background job.
        def lambda_process(data)
          attacher = load(data)
          cached_file = attacher.uploaded_file(data['attachment'])
          attacher.lambda_process(cached_file)
          attacher
        end

        def lambda_authorized?(headers, body)
          incoming_auth_header = auth_header_hash(headers['Authorization'])
          signer = build_signer(incoming_auth_header['Credential'].split('/'), headers['x-amz-security-token'])
          signature = signer.sign_request(
            http_method: 'PUT',
            url: Shrine.opts[:callback_url],
            headers: { 'X-Amz-Date' => headers['X-Amz-Date'] },
            body: body
          )
          calculated_signature = auth_header_hash(signature.headers['authorization'])['Signature']
          true if incoming_auth_header['Signature'] == calculated_signature
        end

        private

        def build_signer(headers, security_token = nil)
          credentials = Aws::SharedCredentials.new(profile_name: 'default').credentials
          Aws::Sigv4::Signer.new(
            service: headers[3],
            region: headers[2],
            access_key_id: credentials.access_key_id,
            secret_access_key: credentials.secret_access_key,
            session_token: security_token,
            apply_checksum_header: false,
            unsigned_headers: %w[content-length user-agent x-amzn-trace-id]
          )
        end

        def auth_header_hash(headers)
          auth_header = headers.split(/ |, |=/)
          auth_header.shift
          Hash[*auth_header]
        end
      end

      module AttacherMethods
        # Triggers AWS Lambda processing defined by the user in the uploader's
        # `Shrine#lambda_process`.
        #
        # After the AWS Lambda function was invoked, the response is saved
        # into the cached file's metadata, which can then be reloaded at will for
        # checking progress of the assembly.
        #
        # It raises a `Shrine::Error` if AWS Lambda returned an error.
        def lambda_process(cached_file)
          function, assembly = store.lambda_process(context)
          response = lambda_client.invoke(function_name: function,
                                          invocation_type: 'Event',
                                          payload: { storages:    Shrine.opts[:buckets],
                                                     path:        store.generate_location(cached_file, context),
                                                     callbackURL: Shrine.opts[:callback_url],
                                                     original: cached_file,
                                                     targetStorage: Shrine.opts[:target_storage],
                                                     versions: assembly,
                                                     context: { record_id: context[:record].id,
                                                                name: context[:name] } }.to_json)
          raise Error, "#{response.function_error}: #{response.payload.read}" if response.function_error
          cached_file.metadata['lambda_response'] = response.payload
          swap(cached_file) || _set(cached_file)
        end

        # A cached instance of an AWS Lambda client.
        def lambda_client
          @lambda_client ||= self.class.lambda_client
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
