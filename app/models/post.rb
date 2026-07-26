# frozen_string_literal: true

# A Bookface post — backed by DynamoDB via Dynamoid (this app is generated with
# --skip-active-record). The table is created by the CDK stack; its name is
# resolved in config (config/dynamodb.yml). The author is a Cognito user (we
# store their `sub` and display name; Cognito is the system of record for users).
class Post
  include Dynamoid::Document

  table name: Rails.application.config.x.dynamodb.posts_table.to_sym, key: :id

  field :author_sub
  field :author_name
  field :body

  # Denormalized reaction cache: { "👍" => 12, "❤️" => 3, … }. Kept in step with
  # the per-user Reaction items transactionally (see Reaction.toggle), so reading
  # counts never touches the reactions table.
  field :reactions, :raw, default: {}

  # Attached images: a list of { key, type, content_type, width, height }. Only
  # S3 object references — the bytes live in S3, uploaded straight from the
  # browser (see MediaStorage).
  field :media, :raw, default: []

  # Every post shares this one partition value so the whole feed reads as a
  # single Query on the by-recency GSI below — see `.recent`.
  FEED_PARTITION = "POST"
  field :feed_pk, :string, default: FEED_PARTITION

  # Read the feed newest-first from the server, not in Ruby: a Query on the
  # constant feed partition, ordered by the range key (created_at). The name is
  # explicit and stable so it never depends on the (environment-specific,
  # CDK-generated) table name — the CDK creates the GSI under the same name.
  global_secondary_index name: "posts_by_recency", hash_key: :feed_pk,
                         range_key: :created_at, projected_attributes: :all

  # A post needs an author and *something* to show — text or a photo (or both).
  # Body isn't required on its own: an image-only post is fine.
  validates :author_sub, presence: true
  validates :body, length: { maximum: 5_000 }
  validate :body_or_media

  # This post's reaction address (see Reaction / the reactions bar).
  def reaction_target
    "post"
  end

  # The cache, cleaned for display: string emoji keys, positive counts only.
  def reaction_counts
    (reactions || {}).transform_keys(&:to_s).transform_values(&:to_i).select { |_e, n| n.positive? }
  end

  # Newest first, straight from the by-recency GSI: one Query on the feed
  # partition with the range key (created_at) walked in reverse. No table Scan,
  # no Ruby-side sort. Materialized (the feed view both checks empty? and
  # iterates).
  def self.recent
    where(feed_pk: FEED_PARTITION).scan_index_forward(false).to_a
  end

  def author
    User.new("sub" => author_sub, "name" => author_name)
  end

  # How many comments/replies this post has — a Query on the comments table by
  # post_id (its hash key). Shown next to the feed's "comments" link.
  def comment_count
    Comment.where(post_id: id).count
  end

  # Delete the post and everything under it — every comment in the thread and
  # every reaction (all colocated by post_id) via BatchWriteItem, then reap the
  # attached images from S3 — so nothing is left dangling in either store.
  # DynamoDB goes first, S3 last: a failure can only ever leave orphaned bytes
  # (invisible, recoverable), never a post pointing at images that are gone.
  def destroy_with_thread!
    keys = media_keys # capture before the record goes away
    Comment.where(post_id: id).delete_all
    Reaction.where(post_id: id).delete_all
    delete
    MediaStorage.delete_objects(keys)
  end

  # Attached images with string keys, for the view.
  def media_items
    Array(media).map { |m| m.respond_to?(:transform_keys) ? m.transform_keys(&:to_s) : m }
  end

  # The S3 object keys of the attached images.
  def media_keys
    media_items.filter_map { |m| m["key"] }
  end

  private

  def body_or_media
    return if body.present? || media.present?

    errors.add(:base, "Add something to say or a photo.")
  end
end
