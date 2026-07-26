# frozen_string_literal: true

# A Bookface post — backed by DynamoDB via Dynamoid (this app is generated with
# --skip-active-record). The table is created by the CDK stack; its name arrives
# at runtime via POSTS_TABLE. The author is a Cognito user (we store their `sub`
# and display name; Cognito is the system of record for users).
class Post
  include Dynamoid::Document

  table name: ENV.fetch("POSTS_TABLE", "bookface-posts").to_sym, key: :id

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

  validates :body, presence: true, length: { maximum: 5_000 }
  validates :author_sub, presence: true

  # This post's reaction address (see Reaction / the reactions bar).
  def reaction_target
    "post"
  end

  # The cache, cleaned for display: string emoji keys, positive counts only.
  def reaction_counts
    (reactions || {}).transform_keys(&:to_s).transform_values(&:to_i).select { |_e, n| n.positive? }
  end

  # Newest first. A real feed would use a GSI on a time key; for the demo a
  # scan-and-sort keeps the model readable.
  def self.recent
    all.sort_by { |p| p.created_at || Time.at(0) }.reverse
  end

  def author
    User.new("sub" => author_sub, "name" => author_name)
  end

  # How many comments/replies this post has — a Query on the comments table by
  # post_id (its hash key). Shown next to the feed's "comments" link.
  def comment_count
    Comment.where(post_id: id).count
  end

  # Attached images with string keys, for the view.
  def media_items
    Array(media).map { |m| m.respond_to?(:transform_keys) ? m.transform_keys(&:to_s) : m }
  end
end
