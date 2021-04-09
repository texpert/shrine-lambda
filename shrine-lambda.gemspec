# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)

require 'shrine/plugins/lambda/version.rb'

Gem::Specification.new do |gem|
  gem.name          = 'shrine-lambda'
  gem.version       = Shrine::Plugins::Lambda::VERSION
  gem.authors      = ['Aurel Branzeanu']
  gem.email        = ['branzeanu.aurel@gmail.com']
  gem.homepage     = 'https://github.com/texpert/shrine-lambda'
  gem.summary      = 'AWS Lambda integration plugin for Shrine.'
  gem.description  = <<~DESC
    AWS Lambda integration plugin for Shrine File Attachment toolkit for Ruby applications.
    Used for invoking AWS Lambda functions for processing files already stored in some AWS S3 bucket.
  DESC
  gem.license = 'MIT'
  gem.files        = Dir['CHANGELOG.md', 'README.md', 'LICENSE', 'lib/**/*.rb', '*.gemspec']
  gem.require_path = 'lib/shrine/plugins'

  gem.metadata = { 'bug_tracker_uri' => 'https://github.com/texpert/shrine-lambda/issues',
                   'changelog_uri'   => 'https://github.com/texpert/shrine-lambda/CHANGELOG.md',
                   'source_code_uri' => 'https://github.com/texpert/shrine-lambda' }

  gem.required_ruby_version = '>= 2.3'

  gem.add_dependency 'aws-sdk-lambda', '~> 1.0'
  gem.add_dependency 'aws-sdk-s3', '~> 1.2'
  gem.add_dependency 'shrine', '>= 2.6', '< 4.0'

  gem.add_development_dependency 'activerecord', '>= 4.2.0'
  gem.add_development_dependency 'dotenv'
  gem.add_development_dependency 'github_changelog_generator'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'rubocop', '0.81'
  gem.add_development_dependency 'sqlite3' unless RUBY_ENGINE == 'jruby'

  gem.post_install_message = <<~POSTINSTALL
    DEPRECATION NOTICE: shrine-lambda gem will be renamed to shrine-aws-lambda for clarity

    The current version, 0.1.1, is the last version under the shrine-lambda name.

    Thank you for using this gem!
  POSTINSTALL
end
