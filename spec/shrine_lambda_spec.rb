# frozen_string_literal: true

require 'spec_helper'

require 'active_record'
require 'shrine'
require 'shrine/plugins/activerecord'
require 'shrine/plugins/logging'
require 'shrine/storage/s3'
require 'shrine-lambda'

RSpec.describe Shrine::Plugins::Lambda do
  let(:shrine) { Class.new(Shrine) }
  let(:attacher) { shrine::Attacher.new }
  let(:uploader) { Class.new(Shrine) }
  let(:settings) { Shrine::Plugins::Lambda::SETTINGS.dup }

  before do
    shrine.storages[:store] = s3(bucket: 'store')
    shrine.storages[:cache] = s3(bucket: 'cache')
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
      Shrine.plugin :activerecord
      Shrine.plugin :backgrounding
      Shrine.plugin :lambda, settings

      Shrine::Attacher.promote do |data|
        Shrine::Attacher.lambda_process(data)
      end

      Shrine.storages[:store] = s3(bucket: 'store')
      Shrine.storages[:cache] = s3(bucket: 'cache')

      ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
      ActiveRecord::Base.connection.create_table(:users) do |t|
        t.string :name
        t.text :avatar_data
      end
      ActiveRecord::Base.raise_in_transactional_callbacks = true if ActiveRecord.version < Gem::Version.new('5.0.0')

      user_class = Object.const_set('User', Class.new(ActiveRecord::Base))
      user_class.table_name = :users
      user_class.include uploader.attachment(:avatar)

      @user = user_class.new
      @attacher = @user.avatar_attacher
    end

    after do
      ActiveRecord::Base.remove_connection
      Object.__send__(:remove_const, 'User')
    end

    describe '#lambda_process' do
      it 'loads the attacher and calls lambda_process on the attacher instance' do
        allow(Shrine::Attacher).to receive(:load).and_call_original
        allow_any_instance_of(Shrine::Attacher).to receive(:lambda_process)

        expect(Shrine::Attacher).to receive(:load)
        expect_any_instance_of(Shrine::Attacher).to receive(:lambda_process)

        @user.avatar = FakeIO.new('file', filename: 'some_file.jpg')
        @user.save!
        @user
      end
    end
  end

  def s3(bucket: nil, **options)
    Shrine::Storage::S3.new(bucket: bucket, stub_responses: true, **options)
  end
end
