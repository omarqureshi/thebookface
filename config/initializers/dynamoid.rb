# frozen_string_literal: true

require "dynamoid"

# Dynamoid talks to DynamoDB. The tables themselves are created by the CDK stack
# in infra/ and their real names are handed to the app at runtime (POSTS_TABLE /
# COMMENTS_TABLE), so nothing is hardcoded on either side.
Dynamoid.configure do |config|
  config.region = ENV.fetch("AWS_REGION", "us-east-1")

  if Rails.env.local?
    # Local dev and test run against DynamoDB Local (see compose.yaml) with
    # throw-away credentials — no AWS account needed. `bin/rails
    # dynamoid:create_tables` creates the tables once it's up.
    config.endpoint = ENV.fetch("DYNAMODB_ENDPOINT", "http://localhost:8000")
    config.access_key = ENV.fetch("AWS_ACCESS_KEY_ID", "local")
    config.secret_key = ENV.fetch("AWS_SECRET_ACCESS_KEY", "local")
  elsif ENV["DYNAMODB_ENDPOINT"].present?
    config.endpoint = ENV["DYNAMODB_ENDPOINT"]
  end
  # On Lambda neither branch fires: the SDK uses the real service with the
  # function's IAM role.

  # No namespace prefix — the model's `table name:` is used verbatim so it
  # matches the CDK-created table exactly.
  config.namespace = nil

  config.logger = false
end
