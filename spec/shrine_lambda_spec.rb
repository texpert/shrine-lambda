# frozen_string_literal: true

require 'spec_helper'

require 'active_record'
require 'shrine'
require 'shrine/plugins/activerecord'
require 'shrine/plugins/logging'
require 'shrine/storage/s3'
require 'shrine-lambda'

class LambdaUploader < Shrine
  plugin :versions

  def lambda_process_versions(io, context)
    assembly = { function: 'ImageResizeOnDemand' } # Here the AWS Lambda function name is specified

    # Check if the original file format is a image format supported by the Sharp.js library
    if %w[image/gif image/jpeg image/png image/tiff image/webm].include?(io&.data&.dig('metadata', 'mime_type'))
      case context[:name]
        when :avatar
          assembly[:versions] =
            [{ name: :size40, storage: :store, width: 40, height: 40, format: :jpg }]
      end
    end
    assembly
  end
end

RSpec.describe Shrine::Plugins::Lambda do
  let(:filename) { 'some_file.png' }
  let(:shrine) { Class.new(Shrine) }
  let(:lambda_uploader) { Class.new(LambdaUploader) }
  let(:settings) { Shrine::Plugins::Lambda::SETTINGS.dup }
  let(:attachment_base_data) do
    { 'record'       => %w[User 1], 'name' => 'avatar',
      'shrine_class' => nil, 'action' => 'store', 'phase' => 'store' }
  end

  describe '#configure' do
    context 'when a known option is passed' do
      before { shrine.plugin :lambda, settings }

      it "sets the received options as uploader's options" do
        expect(shrine.opts).to include(settings)
      end

      it 'set the backgrounding_promote option to uploader' do
        expect(shrine.opts[:backgrounding_promote].inspect)
          .to include('shrine-lambda/lib/shrine/plugins/shrine-lambda.rb:')
      end
    end

    context 'when an option with an unknown key is passed' do
      let(:option) { { callback_url: 'some_url', unknown_key: 'some value' } }

      context 'when Shrine logger is enabled' do
        it 'logs the unsupported options' do
          shrine.plugin :logging

          expect_logged("The :unknown_key option is not supported by the Lambda plugin\n", shrine) do
            shrine.plugin :lambda, option
          end
        end
      end

      context 'when Shrine logger is not enabled' do
        it "doesn't log the unsupported options" do
          expect_logged(nil) { shrine.plugin :lambda, option }
        end
      end
    end

    context 'when a required option is not passed' do
      let(:option) { { access_key_id: 'some value' } }

      it 'raise error' do
        expect { shrine.plugin :lambda, option }
          .to raise_exception(Shrine::Plugins::Lambda::Error, 'The :callback_url option is required for Lambda plugin')
      end
    end
  end

  describe '#load_dependencies' do
    context 'when the plugin is registered' do
      before { allow(shrine).to receive(:plugin).with(:lambda, settings).and_call_original }

      it 'is loading its dependencies via load_dependencies class method' do
        expect(Shrine::Plugins::Lambda).to receive(:load_dependencies).with(shrine, settings)
      end

      it "is registering its dependencies via Shrine's plugin method" do
        expect(shrine).to receive(:plugin).with(:lambda, settings)
        expect(shrine).to receive(:plugin).with(:backgrounding)
      end

      after { shrine.plugin :lambda, settings }
    end
  end

  describe 'AttacherClassMethods' do
    before do
      configure_uploader_class(Shrine)
      configure_uploader_instance(shrine)
    end

    after do
      ActiveRecord::Base.remove_connection
      Object.__send__(:remove_const, 'User')
    end

    describe '#lambda_process' do
      context 'when saving user with an attached avatar, the Attacher class method lambda_process is called' do
        it 'loads the attacher and calls lambda_process on the attacher instance' do
          @user.avatar = FakeIO.new('file', filename: filename)
          data = { 'attachment' => @user.avatar_data }.merge!(attachment_base_data)

          allow(Shrine::Attacher).to receive(:lambda_process).and_call_original
          allow(Shrine::Attacher).to receive(:load).and_call_original
          allow_any_instance_of(Shrine::Attacher).to receive(:lambda_process)

          expect(Shrine::Attacher).to receive(:lambda_process).with(data)
          expect(Shrine::Attacher).to receive(:load).with(data)
          expect_any_instance_of(Shrine::Attacher).to receive(:lambda_process).with(data)

          @user.save!
        end
      end

      context 'when saving user with no attached avatar' do
        it 'the Attacher class method lambda_process is not called' do
          allow(Shrine::Attacher).to receive(:lambda_process).and_call_original

          expect(Shrine::Attacher).not_to receive(:lambda_process)

          @user.save!
        end
      end
    end

    describe '#lambda_authorize' do
      let(:headers) { JSON.parse(File.read("#{RSPEC_ROOT}/fixtures/event_headers.json")) }
      let(:body) { File.read("#{RSPEC_ROOT}/fixtures/event_body.txt") }
      let(:shrine_context) { JSON.parse(body).delete('context') }
      let(:auth_header) do
        { 'Credential'    => 'AKIAI2YBN2CKB6DH77ZQ/20200307/us-east-1/handler/aws4_request',
          'SignedHeaders' => 'host;x-amz-date',
          'Signature'     => '693c6c6232b5494660d5aed1e7b6f2c8995d2ccc0cc0123545eccbbfc9bf8f9a' }
      end
      let(:signature) { double('Aws::Sigv4::Signature') }

      before do
        @user.save!

        allow(Shrine::Attacher).to receive(:load).and_call_original
      end

      context 'when signature in received headers matches locally computed AWS signature' do
        it 'returns the attacher and the hash of the parsed result from Lambda' do
          expect(Shrine::Attacher).to receive(:load).with(shrine_context).and_return(@user.avatar_attacher)

          allow(Shrine::Attacher).to receive(:auth_header_hash).and_call_original
          expect(Shrine::Attacher)
            .to receive(:auth_header_hash).with(headers['Authorization']).and_return(auth_header)

          allow(Shrine::Attacher).to receive(:build_signer).and_call_original
          expect(Shrine::Attacher).to receive(:build_signer)

          allow_any_instance_of(Aws::Sigv4::Signer).to receive(:sign_request).and_return(signature)
          expect_any_instance_of(Aws::Sigv4::Signer)
            .to receive(:sign_request).with(http_method: 'PUT',
                                            url:         Shrine.opts[:callback_url],
                                            headers:     { 'X-Amz-Date' => headers['X-Amz-Date'] },
                                            body:        body)

          allow(signature).to receive(:headers).and_return('authorization' => headers['Authorization'])

          result = Shrine::Attacher.lambda_authorize(headers, body)

          expect(result).to eql([@user.avatar_attacher, JSON.parse(body).except('context')])
        end
      end

      context 'when signature in received headers does not match locally computed AWS signature' do
        it 'returns false' do
          allow_any_instance_of(Aws::Sigv4::Signer).to receive(:sign_request).and_return(signature)

          allow(signature).to receive(:headers).and_return('authorization' => headers['Authorization'].chop)

          result = Shrine::Attacher.lambda_authorize(headers, body)

          expect(result).to be(false)
        end
      end
    end
  end

  describe 'Attacher instance methods' do
    before do
      configure_uploader_class(LambdaUploader)
      configure_uploader_instance(lambda_uploader)
    end

    after do
      ActiveRecord::Base.remove_connection
      Object.__send__(:remove_const, 'User')
    end

    describe '#lambda_process' do
      it 'invokes the lmbda function and saves file storage info and metadata into the DB model' do
        @user.avatar = FakeIO.new('file', filename: filename, content_type: 'image/png')

        allow_any_instance_of(Shrine::Plugins::Lambda::AttacherMethods)
          .to receive(:function_available?).and_return(true)

        expect_any_instance_of(LambdaUploader).to receive(:lambda_process_versions).and_call_original
        allow_any_instance_of(Shrine::Plugins::Lambda::AttacherMethods).to receive(:prepare_assembly)
        expect_any_instance_of(Shrine::Plugins::Lambda::AttacherMethods).to receive(:prepare_assembly)

        aws_lambda_client = Aws::Lambda::Client.new(stub_responses: true)
        allow_any_instance_of(Shrine::Plugins::Lambda::AttacherMethods)
          .to receive(:lambda_client).and_return(aws_lambda_client)

        aws_lambda_client.stub_responses(:invoke, { status_code: 200, headers: { 'header-name' => 'header-value' },
                                                    body: { function_error: '' }.to_json })

        @user.save!
        @user.reload.avatar_data

        expect(@user.avatar.storage_key).to eql('cache')
        expect(@user.avatar.metadata['filename']).to eql(filename)
        expect(@user.avatar.metadata['mime_type']).to eql('image/png')
      end
    end
  end
end
