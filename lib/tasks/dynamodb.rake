# frozen_string_literal: true

namespace :dynamodb do
  # Posts written before the by-recency GSI (see Post.recent) have no feed_pk, so
  # they're absent from the index and drop out of the feed. Stamp the constant
  # partition value on every post so they all appear again.
  #
  # This is a per-item UpdateItem, not a BatchWriteItem: DynamoDB's batch write
  # only does full Put/Delete (no batch update), and a full Put would risk
  # clobbering other attributes — UpdateItem sets feed_pk alone, leaving
  # created_at (the GSI's range key) untouched. Setting the same constant is
  # idempotent, so the task is safe to re-run.
  desc "Backfill feed_pk on every Post so it appears in the by-recency feed index"
  task backfill_feed_pk: :environment do
    count = 0
    Post.all.each do |post|
      Post.update_fields(post.id, nil, feed_pk: Post::FEED_PARTITION)
      count += 1
    end
    puts "feed_pk backfilled on #{count} post(s)."
  end
end
