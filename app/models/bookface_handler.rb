# frozen_string_literal: true

# The Lambda entrypoint (wired as the image cmd in infra/). The same function
# serves two event shapes: normal HTTP invocations (the Function URL) go to
# Lamby's Rack adapter unchanged, while messages from the profile-reconcile SQS
# queue are detected here and run the reconcile for each sub. HTTP is byte-for-
# byte the old behaviour — only SQS events take the new branch.
#
# Named BookfaceHandler, not LambdaHandler, because aws_lambda_ric already owns
# the LambdaHandler constant.
module BookfaceHandler
  module_function

  def call(event:, context:)
    if (records = sqs_records(event))
      reconcile(records)
    else
      Lamby.cmd(event: event, context: context)
    end
  end

  # SQS batch events carry Records tagged with this eventSource; HTTP events (the
  # Function URL) have no Records, so they fall through to Lamby untouched.
  def sqs_records(event)
    records = event["Records"]
    records if records.is_a?(Array) && records.all? { |r| r["eventSource"] == "aws:sqs" }
  end

  # Each message body is a user sub. The reconcile is idempotent, so a redelivery
  # is harmless; a raised error leaves the message on the queue to retry and, past
  # the redrive limit, land in the DLQ.
  def reconcile(records)
    records.each do |record|
      sub = record["body"].to_s
      ProfileReconciliation.run(sub) unless sub.empty?
    end
    nil
  end
end
