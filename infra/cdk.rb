# frozen_string_literal: true

require "aws-cdk-lib"
require_relative "config/environments"
require_relative "stacks/bookface_stack"

app = AWSCDK::App.new

# Choose an environment with `-c env=staging` (or STAGE=staging) to synth/deploy
# just one; otherwise every environment is synthesised, so you can also target one
# by stack name (`cdk deploy TheBookface-staging`).
selected = app.node.try_get_context("env") || ENV["STAGE"]
environments =
  if selected
    { selected => Bookface::ENVIRONMENTS.fetch(selected) { abort("unknown env #{selected.inspect}") } }
  else
    Bookface::ENVIRONMENTS
  end

environments.each do |name, config|
  BookfaceStack.new(
    app,
    "TheBookface-#{name}",
    env_name: name,
    config: config,
    env: AWSCDK::Environment.new(
      account: config[:account] || ENV["CDK_DEFAULT_ACCOUNT"],
      region: config[:region] || ENV.fetch("CDK_DEFAULT_REGION", "us-east-1")
    )
  )
end

app.synth
