# frozen_string_literal: true

require 'stringio'

module LoggingHelper
  def expect_logged(pattern, obj = nil)
    result = nil
    logged = capture_logged_by(obj) do
      result = yield
    end

    expect(pattern).to match logged

    result
  end

  def capture_logged_by(object)
    return unless object

    begin
      previous_logger = object.logger
      output = StringIO.new
      object.logger = Logger.new(output)
      object.logger.formatter = ->(*, message) { "#{message}\n" }

      yield

      output.string
    ensure
      object.logger = previous_logger
    end
  end
end
