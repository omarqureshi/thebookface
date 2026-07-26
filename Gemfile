source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "puma", ">= 5.0"

# base64 became a bundled (non-default) gem in Ruby 3.4+, and the app uses Base64
# directly (encoding comment paths into URL segments / DOM ids), so declare it
# rather than lean on a transitive copy. Bundler.require then loads it app-wide —
# no scattered `require "base64"`.
gem "base64"

# --- Running on AWS Lambda -------------------------------------------------
# Lamby adapts the Lambda event (Function URL / API Gateway / ALB) to Rack; the
# handler is config/environment.Lamby.cmd (see the Dockerfile). aws_lambda_ric is
# the Lambda Runtime Interface Client — the image ENTRYPOINT — kept inside the
# bundle so bundler can activate it.
gem "lamby", "~> 7.0"
gem "aws_lambda_ric", "~> 3.2"

# X-Ray tracing — loaded only on Lambda (see config/initializers/xray.rb). The
# function runs with X-Ray active tracing (infra/), so requiring the SDK's Lambda
# entrypoint installs a facade context + patches the aws-sdk so DynamoDB/S3 calls
# show up as subsegments under the invocation. require:false keeps it (and its Rack
# middleware, which would create a conflicting segment) out of local Puma + tests.
gem "aws-xray-sdk", "~> 0.16.0", require: false

# --- Data: DynamoDB via Dynamoid ------------------------------------------
# No Active Record (--skip-active-record). Post and Comment are Dynamoid
# documents; the tables are created by the CDK stack in infra/ and their names
# are handed in at runtime via env vars.
gem "dynamoid", "~> 3.10"
gem "aws-sdk-dynamodb", "~> 1"

# Media (images) live in S3, uploaded straight from the browser with presigned
# POSTs — bytes never pass through Lambda. Served via CloudFront in production;
# MinIO stands in for S3 locally (see compose.yaml).
gem "aws-sdk-s3", "~> 1"

# --- Auth: Cognito (Google social login) over OIDC ------------------------
# The app speaks OIDC to the Cognito user pool; Google is configured as a
# federated identity provider *inside* Cognito, so the app only ever talks to
# Cognito. rails_csrf_protection guards the request phase.
gem "omniauth_openid_connect", "~> 0.8"
gem "omniauth-rails_csrf_protection", "~> 1.0"

# Authorization: who may edit/delete what. Ownership is a plain attribute match
# (author_sub), so CanCanCan works fine over our Dynamoid documents + the
# session-backed user (we authorize already-loaded objects; no accessible_by).
gem "cancancan", "~> 3.6"

# --- Assets: no Node, no build step ---------------------------------------
# Stimulus/Turbo ship over an importmap; propshaft only fingerprints. Rails
# serves /assets itself in the demo (RAILS_SERVE_STATIC_FILES); in front of real
# traffic you'd add CloudFront so asset requests never reach Lambda.
gem "propshaft"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"

gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  # RSpec for fast, DB-free model/unit specs (Cucumber still covers integration).
  gem "rspec-rails"
end

group :test do
  # Feature tests. Capybara drives with rack_test (no browser needed); the app's
  # own dev-login is reused as the "stubbed" sign-in.
  gem "cucumber-rails", require: false
  gem "capybara"
  gem "rspec-expectations" # expect(...).to have_content(...) in steps
  # Headless-Chrome driver for the @javascript scenarios (the real browser
  # image-upload path). Runs in the test container (see Dockerfile.test).
  gem "cuprite"
end

group :development do
  gem "web-console"
end
