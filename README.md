# Out of maintenance

This gem is now archived, being replaced by the [shrine-aws-lambda](https://github.com/texpert/shrine-aws-lambda)

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
Shrine-Lambda's setup. So, the invoking application must provide a HTTP endpoint (a webhook) to catch the results.

#### Setup

Add Shrine-Lambda gem to the application's Gemfile:

```ruby
gem 'shrine-lambda'
```

Run `$ bundle install` command in the application's root folder to install the gem.


Note, that for working with AWS, the AWS credentials (the `access_key_id` and the `secret_access_key`) should be set 
either in the [Shrine] initializer, or in [default profile][AWS profiles] in the `~/.aws` folder.

```ruby
# config/initializers/shrine.rb:

# ...

  s3_options = { access_key_id:     'your_aws_access_key_id',
                 secret_access_key: 'your_aws_secret_access_key',
                 region:            'your AWS bucket region' }
```

Also, for Lamda functions to work, various [AWS Lamda permissions] should be managed on the [Amazon Web Services] side.

Add to the [Shrine]'s initializer file the Shrine-Lambda plugin registration with the `:callback_url` parameter, and 
the [AWS Lambda] functions list retrieval call (which will retrieve the functions list on application initialization 
and will store the list into the `Shrine.opts[:lambda_function_list]` for further checking):

```ruby
# config/initializers/shrine.rb:

# ...

  Shrine.plugin :lambda, s3_options.merge(callback_url: "https://#{ENV.fetch('APP_HOST')}/lambda")
  Shrine.lambda_function_list
```

By default, Shrine-Lambda is using the S3 bucket named `:cache` for retrieving the original file, and the `:store` 
named S3 bucket for storing the resulting files.

Srine-Lamda uses the [Shrine backgrounding plugin] for asynchronous operation, so this plugin should be also included
 into the Shrine's initializer.

Here is a full example of a Shrine initializer of a [Rails] application using [Roda] endpoints for presigned_url's 
(used for direct file uploads to [AWS S3]) and [AWS Lambda] callbacks:

```ruby
# config/initializers/shrine.rb:

# frozen_string_literal: true

require 'shrine'

if Rails.env.test?
  require 'shrine/storage/file_system'

  Shrine.storages = {
    cache: Shrine::Storage::FileSystem.new('public', prefix: 'uploads/cache'), 
    store: Shrine::Storage::FileSystem.new('public', prefix: 'uploads/store'),
  }
else
  require 'shrine/storage/s3'

  secrets = Rails.application.secrets

  s3_options = { access_key_id:     secrets.aws_access_key_id,
                 secret_access_key: secrets.aws_secret_access_key,
                 region:            'us-east-2' }

  if Rails.env.production?
    cache_bucket = store_bucket = secrets.aws_s3_bucket
  else
    cache_bucket = 'texpert-test-cache'
    store_bucket = 'texpert-test-store'
  end

  Shrine.storages = {
    cache: Shrine::Storage::S3.new(prefix: 'cache', **s3_options.merge(bucket: cache_bucket)),
    store: Shrine::Storage::S3.new(prefix: 'store', **s3_options.merge(bucket: store_bucket))
  }

  lambda_callback_url = if Rails.env.development?
                          "http://#{ENV['USER']}.localtunnel.me/rapi/lambda"
                        else
                          "https://#{ENV.fetch('APP_HOST')}/rapi/lambda"
                        end

  Shrine.plugin :lambda, s3_options.merge(callback_url: lambda_callback_url)
  Shrine.lambda_function_list

  Shrine.plugin :presign_endpoint, presign_options: ->(request) do
    filename     = request.params['filename']
    extension    = File.extname(filename)
    content_type = Rack::Mime.mime_type(extension)

    {
      content_length_range: 0..1.gigabyte,                         # limit filesize to 1 GB
      content_disposition: "attachment; filename=\"#{filename}\"", # download with original filename
      content_type:        content_type,                           # set correct content type
    }
  end
end

Shrine.plugin :activerecord
Shrine.plugin :backgrounding
Shrine.plugin :cached_attachment_data # for forms
Shrine.plugin :logging, logger: Rails.logger
Shrine.plugin :rack_file # for non-Rails apps
Shrine.plugin :remote_url, max_size: 1.gigabyte

Shrine::Attacher.promote { |data| PromoteJob.perform_later(data) }
Shrine::Attacher.delete { |data| DeleteJob.perform_later(data) }

```

Take notice that the promote job is a default `Shrine::Attacher.promote { |data| PromoteJob.perform_later(data) }`. 
This is made to be able to use other than AWS storages in the test environment (like Shrine's `FileSystem` storage) 
and, also, other uploaders which are not using [AWS Lambda]. This job better to be overrided to a `LambdaPromoteJob` 
 directly in the uploaders' classes which will use [AWS Lambda]. 
 
Another thing used in this initializer is the [localtunnel] application for exposing the localhost to the world for 
catching the Lambda callback requests.

#### How it works

Shrine-Lamnda works in such a way that an "assembly" should be created in the `LambdaUploader`, which contains all 
the information about how the file should be processed. A random generated string is appended to the assembly, stored 
into the cached file metadata, and used by the Lambda function to sign the requests to the `:lambda_callback_url`, 
along with the `:access_key_id` from the temporary credentials Lambda function is running with.

Processing itself happens asynchronously - the invoked Lambda function will issue a PUT HTTP request to the  
`:lambda_callback_url`, specified in the Shrine's initializer, with the request's payload containing the processing  
results.

The request should be intercepted by a endpoint at the `:lambda_callback_url`, and its payload transferred to the 
`lambda_save` method on successful request authorization. 

The authorization is calculatating the HTTP request signature using the random string stored in the cached file and 
the Lambda function's `:access_key_id` received in the request authorization header. Then, the calculated signature is
 compared to the received in the same authorization header Lambda signature.

#### Usage

Shrine-Lambda assemblies are built inside the `#lambda_process_versions` method in the `LambdaUploader` class:

```ruby
# app/uploaders/lambda_uploader.rb:

# frozen_string_literal: true

class LambdaUploader < Uploader
  Attacher.promote { |data| LambdaPromoteJob.perform_later(data) } unless Rails.env.test?

  plugin :upload_options, store: ->(_io, context) do
    if %i[avatar logo].include?(context[:name])
      {acl: "public-read"}
    else
      {acl: "private"}
    end
  end

  plugin :versions

  def lambda_process_versions(io, context)
    assembly = { function: 'ImageResizeOnDemand' } # Here the AWS Lambda function name is specified

    # Check if the original file format is a image format supported by the Sharp.js library
    if %w[image/gif image/jpeg image/pjpeg image/png image/svg+xml image/tiff image/x-tiff image/webm]
      .include?(io&.data&.dig('metadata', 'mime_type'))
      case context[:name]
        when :avatar
          assembly[:versions] =
            [{ name: :size40, storage: :store, width: 40, height: 40, format: :jpg }]
        when :logo
          assembly[:versions] =
            [{ name: :size270_180, storage: :store, width: 270, height: 180, format: :jpg }]
        when :doc
          assembly[:versions] =
            [
              { name: :size40, storage: :store, width: 40, height: 40, format: :png },
              { name: :size80, storage: :store, width: 80, height: 80, format: :jpg },
              { name: :size120, storage: :store, width: 120, height: 120, format: :jpg }
            ]
      end
    end
    assembly
  end
end

```

The above example is built to interact with the [lambda-image-resize] function, which is using the [Sharp] Javascript
library for image processing. It is not yet implemented in this function to use the `:target_storage` as default 
bucket for all the processed files, that's why the `:storage` key is specified on every file version. If the file's 
mime type is not supported by the [Sharp] library, no `:versions` will be inserted into the `:assembly` so the 
original file will just be copied to the `:store` S3 bucket.

The [Shrine upload_options plugin] is used to specify the S3 bucket ACL and the [Shrine versions plugin] is used to 
enable the uploader to deal with different processed versions of the original file.

The default options used by Shrine-Lambda plugin are the following:

```ruby
  { callbackURL:    Shrine.opts[:callback_url],
    copy_original:  true,
    storages:       Shrine.buckets_to_use(%i[cache store]),
    target_storage: :store }
```

These options could be overrided in the `LambdaUploader` specifying them as the `assembly` keys:

```ruby
  assembly[:callbackURL]    = some_callback_url]
  assembly[:copy_original   = false               # If this is `false`, only the processed file versions will be stored     
  assembly[:storages]       = Shrine.buckets_to_use(%i[cache store other_store])
  assembly[:target_storage] = :other_store

```

Any S3 buckets could be specified, as long as the buckets are defined in the Shrine's initializer file.


#### Webhook

A `:callbackUrl` endpoint should be implemented to catch the [AWS Lambda] processing results, authorize, and save them. 
Here is an example of a [Roda] endpoint:

```ruby
# lib/rapi/base.rb:

# frozen_string_literal: true

# On Rails autoload is done by ActiveSupport from the `autoload_paths` - no need to require files
# require 'roda'
# require 'roda/plugins/json'
# require 'roda/plugins/static_routing'

module RAPI
  class Base < Roda
    plugin :json
    plugin :request_headers
    plugin :static_routing

    static_put '/lambda' do
      auth_result = Shrine::Attacher.lambda_authorize(request.headers, request.body.read)
      if !auth_result
        response.status = 403
        { 'Error' => 'Signature mismatch' }
      elsif auth_result.is_a?(Array)
        attacher = auth_result[0]
        if attacher.lambda_save(auth_result[1])
          { 'Result' => 'OK' }
        else
          response.status = 500
          { 'Error' => 'Backend record update error' }
        end
      else
        response.status = 500
        { 'Error' => 'Backend Lambda authorization error' }
      end
    end
  end
end

```

#### Backgrounding

Even though submitting a Lambda assembly doesn't require any uploading, it still does a HTTP request, so it is better 
to put it into a background job. This is configured in the `LambdaUploader` class:

`Attacher.promote { |data| LambdaPromoteJob.perform_later(data) } unless Rails.env.test?`

Then the job file should be implemented:

```ruby
# app/jobs/lambda_promote_job.rb:

# frozen_string_literal: true

class LambdaPromoteJob < ApplicationJob
  def perform(data)
    Timeout.timeout(30) { Shrine::Attacher.lambda_process(data) }
  end
end
```

### Gem Maintenance

#### Preparing a release

Merge all the pull requests that should make it into the new release into the `main` branch, then checkout and pull the
branch and run the `github_changelog_generator`, specifying the new version as a `--future-release` command line 
parameter:

```bash
$ git checkout main
$ git pull

$ github_changelog_generator -u texpert -p shrine-lambda --future-release v0.1.1
```

Then add the changes to `git`, commit and push the `Preparing the new release` commit directly into the `main` branch:

```bash
$ git add .
$ git commit -m 'Preparing the new v0.1.1 release'
$ git push
```

#### RubyGems credentials

Ensure you have the RubyGems credentials located in the `~/.gem/credentials` file.

#### Adding a gem owner

```bash
$ gem owner shrine-lambda -a friend@example.com
```

#### Building a new gem version

Adjust the new gem version number in the `lib/shrine/plugins/lambda/version.rb` file. It is used when building the gem
by the following command:

```bash
$ gem build shrine-lambda.gemspec
```

Assuming the version was set to `0.1.1`, a `shrine-lambda-0.1.1.gem` binary file will be generated at the root of the app (repo).

- The binary file shouldn't be added into the `git` tree, it will be pushed into the RubyGems and to the GitHub releases

#### Pushing a new gem release to RubyGems

```bash
$ gem push shrine-lambda-0.1.1.gem # don't forget to specify the correct version number
```

#### Crafting the new release on GitHub

On the [Releases page](https://github.com/texpert/shrine-lambda/releases) push the `Draft a new release` button.

The new release editing page opens, on which the following actions could be taken:

- Choose the repo branch (default is `main`)
- Insert a tag version (usually, the tag should correspond to the gem's new version, v0.0.1, for example)
 - the tag will be created by GitHub on the last commit into the chosen branch
- Fill the release Title and Description
- Attach the binary file with the generated gem version
- If the release is not yet ready for production, mark the `This is a pre-release` checkbox
- Press either the `Publish release`, or the `Save draft button` if you want to publish it later
 - After publishing the release, the the binary gem file will be available on GitHub and could be removed locally


## Inspiration

I want to thank [Janko Marohnić][Janko] for the awesome [Shrine] gem and, also, for guiding me to look at his  
implementation of a similar plugin - [Shrine-Transloadit].

Also thanks goes to [Tim Uckun] for providing a link to the [article about resizing images on the fly][AWS blog 
article], which pointed me to use the [Sharp] library for image resizing.

## License

[MIT](/LICENSE.txt)

[Amazon]: https://www.amazon.com
[Amazon Web Services]: https://aws.amazon.com
[AWS blog article]: https://aws.amazon.com/blogs/compute/resize-images-on-the-fly-with-amazon-s3-aws-lambda-and-amazon-api-gateway/
[AWS Lambda]: https://aws.amazon.com/lambda
[AWS Lamda permissions]: https://docs.aws.amazon.com/lambda/latest/dg/intro-permission-model.html
[AWS profiles]: https://docs.aws.amazon.com/cli/latest/userguide/cli-multiple-profiles.html
[AWS S3]: https://aws.amazon.com/s3/
[Janko]: https://github.com/janko-m
[lambda-image-resize]: https://github.com/texpert/lambda-image-resize.js
[localtunnel]: https://github.com/localtunnel/localtunnel
[Rails]: http://rubyonrails.org
[Roda]: http://roda.jeremyevans.net
[Sharp]: https://github.com/lovell/sharp
[Shrine]: https://github.com/janko-m/shrine
[Shrine backgrounding plugin]: http://shrinerb.com/rdoc/classes/Shrine/Plugins/Backgrounding.html
[Shrine-Transloadit]: https://github.com/janko-m/shrine-transloadit
[Shrine upload_options plugin]: http://shrinerb.com/rdoc/classes/Shrine/Plugins/UploadOptions.html
[Shrine versions plugin]: http://shrinerb.com/rdoc/classes/Shrine/Plugins/Versions.html
[Tim Uckun]: https://github.com/timuckun
