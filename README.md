# Shrine::Plugins::Lambda
Provides [AWS Lambda] integration for [Shrine] File Attachment toolkit for Ruby applications

## Description

### AWS Lambda

[AWS Lambda] is a serverless computing platform provided by [Amazon] as a part of the [Amazon Web Services]. It is a 
compute service that could run someone's uploaded code in response to events and/or requests, and automatically manages 
and scales the compute resources required by that code.

### Shrine

[Shrine] is the best and most versatile file attachment toolkit for Ruby applications, developed by [Janko 
Marohnić][Janko]. It has a vast collection of plugins with support for direct uploads, background processing and 
deleting, processing on upload or on-the-fly, and ability to use with other ORMs

### Shrine-Lambda

Shrine-Lambda is a plugin for invoking [AWS Lambda] functions for processing files already stored in some [AWS S3 
bucket][AWS S3]. Specifically, it was designed for invoking an image resizing [AWS Lambda] function like [this 
one][lambda-image-resize], but it could be used to invoke any other function, due to [Shrine]'s modular plugin 
architecture design.

The function is invoked to run asynchronously. Function's result will be sent by [AWS Lambda] back to the 
invoking application in a HTTP request's payload. The HTTP request would target a callback URL specified in the 
Shrine-Lambda's setup. So, the invoking application must provide a HTTP endpoint (a web-hook) to catch the results.

#### Setup

Add Shrine-Lambda gem to the application's Gemfile:

```
gem 'shrine-lambda'
```

Run `$ bundle install` command in the application's root folder to install the gem.

Add to the [Shrine]'s initializer file, the plugin registration and [AWS Lambda] functions list retrieval lines:

```
# config/initializers/shrine.rb

...

  lambda_callback_url = if Rails.env.development?
                          "http://#{ENV['USER']}.localtunnel.me/rapi/lambda"
                        else
                          "https://#{ENV.fetch('APP_HOST')}/rapi/lambda"
                        end

  Shrine.plugin :lambda, s3_options.merge(callback_url: lambda_callback_url)
  Shrine.lambda_function_list
```

## License

[MIT](/LICENSE.txt)

[Amazon]: https://www.amazon.com
[Amazon Web Services]: https://aws.amazon.com
[AWS Lambda]: https://aws.amazon.com/lambda
[AWS S3]: https://aws.amazon.com/s3/
[Janko]: https://github.com/janko-m
[lambda-image-resize]: https://github.com/texpert/lambda-image-resize.js
[Shrine]: https://github.com/janko-m/shrine
