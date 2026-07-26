# frozen_string_literal: true

# Loads Rails for specs that need it (model specs, etc.). No Active Record, so
# none of the fixtures / test-schema wiring the rspec:install generator assumes —
# and model validations run in memory, so these specs need no DynamoDB.
require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
