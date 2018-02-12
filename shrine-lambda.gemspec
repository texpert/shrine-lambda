# frozen_string_literal: true

Gem::Specification.new do |gem|
  gem.name          = 'shrine-lambda'
  gem.version       = '0.0.1'

  gem.required_ruby_version = '>= 2.3'

  gem.summary      = 'Provides AWS Lambda integration for Shrine.'
  gem.homepage     = 'https://github.com/texpert/shrine-lambda'
  gem.authors      = ['Aurel Branzeanu']
  gem.email        = ['branzeanu.aurel@gmail.com']
  gem.license      = 'MIT'

  gem.files        = Dir['README.md', 'LICENSE.txt', 'lib/**/*.rb', '*.gemspec']
  gem.require_path = 'lib'

  gem.add_dependency 'aws-sdk-lambda', '~> 1.0'
  gem.add_dependency 'aws-sdk-s3', '~> 1.2'
  gem.add_dependency 'shrine', '~> 2.6'

  gem.add_development_dependency 'dotenv'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rubocop', '~> 0.52'
end
