# frozen_string_literal: true

Gem::Specification.new do |gem|
  gem.name          = 'shrine-lambda'
  gem.version       = '0.0.1'

  gem.required_ruby_version = '>= 2.3'

  gem.summary      = 'AWS Lambda integration plugin for Shrine.'
  gem.homepage     = 'https://github.com/texpert/shrine-lambda'
  gem.authors      = ['Aurel Branzeanu']
  gem.description  = <<-DESC
      AWS Lambda integration plugin for Shrine File Attachment toolkit for Ruby applications.
      Used for invoking AWS Lambda functions for processing files already stored in some AWS S3 bucket.
  DESC
  gem.email        = ['branzeanu.aurel@gmail.com']
  gem.license      = 'MIT'

  gem.files        = Dir['CHANGELOG.md', 'README.md', 'LICENSE', 'lib/**/*.rb', '*.gemspec']
  gem.require_path = 'lib/shrine/plugins'

  gem.metadata = { 'bug_tracker_uri' => 'https://github.com/texpert/shrine-lambda/issues',
                   'changelog_uri'   => 'https://github.com/texpert/shrine-lambda/CHANGELOG.md',
                   'source_code_uri' => 'https://github.com/texpert/shrine-lambda' }

  gem.add_dependency 'aws-sdk-lambda', '~> 1.0'
  gem.add_dependency 'aws-sdk-s3', '~> 1.2'
  gem.add_dependency 'shrine', '~> 2.6'

  gem.add_development_dependency 'dotenv'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rubocop'
end
