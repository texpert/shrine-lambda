# frozen_string_literal: true

require 'aws-sdk-lambda'

class Shrine
  module Plugins
    module Lambda
      Error = Class.new(Shrine::Error)
    end

    register_plugin(:lambda, Lambda)
  end
end
