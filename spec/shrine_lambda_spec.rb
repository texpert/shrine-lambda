# frozen_string_literal: true

require 'spec_helper'

require 'shrine'
require 'shrine/plugins/logging'
require 'shrine/storage/s3'
require 'shrine-lambda'

RSpec.describe Shrine::Plugins::Lambda do
  let(:shrine) { Class.new(Shrine) }
  let(:attacher) { shrine::Attacher.new }
  let(:uploader) { attacher.store }

  before do
    shrine.storages[:store] = s3
  end

  describe '#configure' do
    context 'when a known option is passed' do
      before { shrine.plugin :lambda, Shrine::Plugins::Lambda::SETTINGS.dup }

      it "sets the received options as uploader's options" do
        expect(shrine.opts).to include(Shrine::Plugins::Lambda::SETTINGS)
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

  def s3(**options)
    Shrine::Storage::S3.new(bucket: 'dummy', stub_responses: true, **options)
  end
end
