# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookfaceHandler do
  describe ".call" do
    it "routes an SQS event to the reconcile, one run per message body" do
      event = { "Records" => [
        { "eventSource" => "aws:sqs", "body" => "dev|ada" },
        { "eventSource" => "aws:sqs", "body" => "dev|grace" }
      ] }
      expect(ProfileReconciliation).to receive(:run).with("dev|ada")
      expect(ProfileReconciliation).to receive(:run).with("dev|grace")

      BookfaceHandler.call(event: event, context: nil)
    end

    it "hands a non-SQS (HTTP) event to Lamby unchanged" do
      event = { "requestContext" => { "http" => { "method" => "GET" } } }
      expect(Lamby).to receive(:cmd).with(event: event, context: :ctx)

      BookfaceHandler.call(event: event, context: :ctx)
    end

    it "skips blank message bodies" do
      event = { "Records" => [{ "eventSource" => "aws:sqs", "body" => "" }] }
      expect(ProfileReconciliation).not_to receive(:run)

      BookfaceHandler.call(event: event, context: nil)
    end
  end
end
