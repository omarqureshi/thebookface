# frozen_string_literal: true

# Keeps the denormalized author fields (author_name / author_avatar) on a user's
# posts + comments in step with their profile. Declarative and idempotent: each
# run makes one user's content match their *current* profile, so a message can be
# retried or replayed freely and there's no cursor/last-run to track.
module ProfileReconciliation
  module_function

  # Called after a profile save. In production it drops the sub on the SQS queue
  # (a Lambda consumes it and calls #run), so the save doesn't wait on the
  # fan-out; with no queue configured (local dev/test) it reconciles inline,
  # which keeps the denormalization correct there too.
  def enqueue(sub)
    if queue_url.present?
      sqs.send_message(queue_url: queue_url, message_body: sub)
    else
      run(sub)
    end
  end

  # The reconcile itself — safe to call directly (the rake task + SQS handler do).
  # Returns how many items were rewritten.
  def run(sub)
    profile = Profile.for(sub)
    return 0 unless profile.persisted?

    # author_avatar may legitimately become nil (avatar removed); author_name is
    # only written when we have one, so a reconcile can never wipe a name.
    attrs = { author_avatar: profile.avatar_key }
    attrs[:author_name] = profile.shown_name if profile.shown_name.present?

    count = 0
    Post.where(author_sub: sub).each do |post|
      Post.update_fields(post.id, nil, attrs)
      count += 1
    end
    Comment.where(author_sub: sub).each do |comment|
      Comment.update_fields(comment.post_id, comment.path, attrs)
      count += 1
    end
    count
  end

  # --- internals ---

  def queue_url
    ENV["RECONCILE_QUEUE_URL"]
  end

  def sqs
    require "aws-sdk-sqs" # lazy — only production (with a queue) needs it loaded
    @sqs ||= Aws::SQS::Client.new
  end
end
