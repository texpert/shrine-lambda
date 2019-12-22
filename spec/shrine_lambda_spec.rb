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
  let(:settings) { Shrine::Plugins::Lambda::SETTINGS.dup }

  before do
    shrine.storages[:store] = s3
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

  def s3(**options)
    Shrine::Storage::S3.new(bucket: 'dummy', stub_responses: true, **options)
  end
end
