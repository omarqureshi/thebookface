# frozen_string_literal: true

# DynamoDB / S3 call tracing via the X-Ray SDK — Lambda only.
#
# The function has X-Ray *active tracing* (see infra/stacks/bookface_stack.rb), so
# the Lambda service already opens a segment per invocation and runs the X-Ray
# daemon. Requiring the SDK's Lambda entrypoint installs a facade context bound to
# that segment and patches the aws-sdk (and net/http), so each DynamoDB/S3 call
# emits a subsegment nested under the invocation — no second, conflicting segment.
#
# Gated to Lambda (and the gem is require:false in the Gemfile), so local Puma and
# the test suite are untouched — no daemon, no Rack middleware, no patching.
require "aws-xray-sdk/lambda" if ENV["AWS_LAMBDA_FUNCTION_NAME"].present?
