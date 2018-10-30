# frozen_string_literal: true

require 'aws-sdk-lambda'

class Shrine
  module Plugins
    module Lambda
      SETTINGS = { access_key_id:     :optional,
                   callback_url:      :required,
                   convert_params:    :optional,
                   endpoint:          :optional,
                   log_formatter:     :optional,
                   log_level:         :optional,
                   logger:            :optional,
                   profile:           :optional,
                   region:            :optional,
                   retry_limit:       :optional,
                   secret_access_key: :optional,
                   session_token:     :optional,
                   stub_responses:    :optional,
                   validate_params:   :optional }.freeze

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
          attacher.lambda_process(data)
          attacher
        end

        # Parses the payload of the Lambda request to the `callbackUrl` and loads the Shrine Attacher from the
        # received context.
        # Fetches the signing key from the attacher's record metadata and uses it for calculating the signature of the
        # received from Lambda request. Then it compares the calculated and received signatures, returning an error if
        # the signatures mismatch.
        #
        # If the signatures are equal, it returns the attacher and the hash of the parsed result from Lambda.
        # @param [Hash] headers from the Lambda request
        # @param [String] body of the Lambda request
        # @return [Array] Shrine Attacher and the Lambda result (the request body parsed to a hash).
        def lambda_authorize(headers, body)
          result = JSON.parse(body)
          attacher = load(result.delete('context'))
          incoming_auth_header = auth_header_hash(headers['Authorization'])

          signer = build_signer(incoming_auth_header['Credential'].split('/'),
                                JSON.parse(attacher.record.__send__(:"#{attacher.data_attribute}"))['metadata']['key'],
                                headers['x-amz-security-token'])
          signature = signer.sign_request(
            http_method: 'PUT',
            url:         Shrine.opts[:callback_url],
            headers:     { 'X-Amz-Date' => headers['X-Amz-Date'] },
            body:        body
          )
          calculated_signature = auth_header_hash(signature.headers['authorization'])['Signature']
          return false if incoming_auth_header['Signature'] != calculated_signature

          [attacher, result]
        end

        private

        def build_signer(headers, secret_access_key, security_token = nil)
          Aws::Sigv4::Signer.new(
            service:               headers[3],
            region:                headers[2],
            access_key_id:         headers[0],
            secret_access_key:     secret_access_key,
            session_token:         security_token,
            apply_checksum_header: false,
            unsigned_headers:      %w[content-length user-agent x-amzn-trace-id]
          )
        end

        # @param [String] header is the `Authorization` header string
        # @return [Hash] the `Authorization` header string transformed into a Hash
        def auth_header_hash(header)
          auth_header = header.split(/ |, |=/)
          auth_header.shift
          Hash[*auth_header]
        end
      end

      module AttacherMethods
        # Triggers AWS Lambda processing defined by the user in the uploader's `Shrine#lambda_process`,
        # first checking if the specified Lambda function is available (raising an error if not).
        #
        # Generates a random key, stores the key into the cached file metadata, and passes the key to the Lambda
        # function for signing the request.
        #
        # Stores the DB record class and name, attacher data atribute and uploader class names, into the context
        # attribute of the Lambda function invokation payload. Also stores the cached file hash object and the
        # generated path into the payload.
        #
        # After the AWS Lambda function invocation, a `Shrine::Error` will be raised if the response is containing
        # errors. No more response analysis is performed, because Lambda is invoked asynchronously (note the
        # `invocation_type`: 'Event' in the `invoke` call). The results will be sent by Lambda by HTTP requests to
        # the specified `callbackUrl`.
        def lambda_process(data)
          cached_file = uploaded_file(data['attachment'])
          assembly = Shrine.lambda_default_values
          assembly.merge!(store.lambda_process(cached_file, context))
          function = assembly.delete(:function)
          raise Error, 'No Lambda function specified!' unless function
          raise Error, "Function #{function} not available on Lambda!" unless function_available?(function)

          prepare_assembly(assembly, cached_file, context)
          assembly[:context] = data.except('attachment', 'action', 'phase')
          response = lambda_client.invoke(function_name:   function,
                                          invocation_type: 'Event',
                                          payload:         assembly.to_json)
          raise Error, "#{response.function_error}: #{response.payload.read}" if response.function_error

          swap(cached_file) || _set(cached_file)
        end

        # Receives the `result` hash after Lambda request was authorized. The result could contain an array of
        # processed file versions data hashes, or a single file data hash, if there were no versions and the original
        # attached file was just moved to the target storage bucket.
        #
        # Deletes the signing key, if it is present in the original file's metadata, converts the result to a JSON
        # string, and writes this string into the `data_attribute` of the Shrine attacher's record.
        #
        # Chooses the `save_methodz` either for the ActiveRecord or for Sequel, and saves the record.
        # @param [Hash] result
        def lambda_save(result)
          versions = result['versions']
          attr_content = if versions
                           tmp_hash = versions.inject(:merge!)
                           tmp_hash.dig('original', 'metadata')&.delete('key')
                           tmp_hash.to_json
                         else
                           result['metadata']&.delete('key')
                           result.to_json
                         end

          record.__send__(:"#{data_attribute}=", attr_content)
          save_method = if record.is_a?(ActiveRecord::Base)
                          :save
                        elsif record.is_a?(::Sequel::Model)
                          :save_changes
                        end
          record.__send__(save_method, validate: false)
        end

        private

        # A cached instance of an AWS Lambda client.
        def lambda_client
          @lambda_client ||= Shrine.lambda_client
        end

        # Checks if the specified Lambda function is available.
        # @param [Symbol] function name
        def function_available?(function)
          Shrine.opts[:lambda_function_list].map(&:function_name).include?(function.to_s)
        end

        def prepare_assembly(assembly, cached_file, context)
          assembly[:path] = store.generate_location(cached_file, context)
          assembly[:storages].each do |s|
            upload_options = get_upload_options(cached_file, context, s)
            s[1][:upload_options] = upload_options if upload_options
          end
          cached_file.metadata['key'] = SecureRandom.base64(12)
          assembly[:attachment] = cached_file
        end

        def get_upload_options(cached_file, context, storage)
          options = store.opts[:upload_options][storage[0].to_sym]
          options = options.call(cached_file, context) if options.respond_to?(:call)
          options
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

          opts[:lambda_function_list] = lambda_client.list_functions(master_region:    master_region,
                                                                     function_version: function_version,
                                                                     marker:           marker,
                                                                     max_items:        items).functions
        end

        # @param [Array] buckets that will be sent to Lambda function for use
        def buckets_to_use(buckets)
          buckets.map do |b|
            { b.to_s => { name: Shrine.storages[b].bucket.name, prefix: Shrine.storages[b].prefix } }
          end.inject(:merge!)
        end

        def lambda_default_values
          { callbackURL:    Shrine.opts[:callback_url],
            copy_original:  true,
            storages:       Shrine.buckets_to_use(%i[cache store]),
            target_storage: :store }
        end
      end
    end

    register_plugin(:lambda, Lambda)
  end
end
