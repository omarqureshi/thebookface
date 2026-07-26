# frozen_string_literal: true

# Hierarchical comments on a post, modelled the DynamoDB way: one table, keyed by
# (post_id, path).
#
#   * partition key `post_id` — every comment on a post is colocated, so the whole
#     thread is a single Query.
#   * sort key `path` — a *materialized path*: the chain of time-ordered segment
#     ids from the post down to this comment, joined by "/".
#
# Because DynamoDB returns a Query sorted by the sort key, ordering by `path`
# yields the thread in pre-order (a parent immediately precedes its subtree, and
# siblings are chronological). Depth is just the number of "/" separators — so
# nesting renders straight from one query, no recursion at read time.
#
#   reply to the post   -> path = "<seg>"                    (depth 0)
#   reply to a comment  -> path = "<parent.path>/<seg>"      (depth 1, 2, …)
class Comment
  include Dynamoid::Document

  table name: Rails.application.config.x.dynamodb.comments_table.to_sym, key: :post_id
  range :path # sort key — the materialized path

  # Set on a reply before save; blank means "reply to the post itself".
  field :parent_path
  field :author_sub
  field :author_name   # denormalized snapshot of the author's display name
  field :author_avatar # denormalized snapshot of the author's avatar key (or nil)
  field :body

  # Denormalized reaction cache (see Post#reactions / Reaction.toggle).
  field :reactions, :raw, default: {}

  # Soft-delete flag — a deleted comment that still has replies keeps its node
  # (so the subtree stays threaded) but renders as "[deleted]".
  field :deleted, :boolean, default: false

  # Find a user's comments (for the profile reconcile job) without a Scan.
  global_secondary_index name: "comments_by_author", hash_key: :author_sub,
                         range_key: :created_at, projected_attributes: :keys_only

  validates :body, presence: true, length: { maximum: 5_000 }, unless: :deleted?
  validates :author_sub, presence: true
  validates :post_id, presence: true

  before_validation :build_path, on: :create

  # The whole thread for a post, in render order (pre-order). Sorted by the sort
  # key server-side; `depth` drives indentation in the view.
  def self.thread_for(post_id)
    where(post_id: post_id).to_a
  end

  def depth
    path.to_s.count("/")
  end

  # This comment's stable DOM id / URL fragment: the path with "/" turned to "-"
  # and a "c-" prefix so it's a valid id (e.g. "c-ab12-cd34"). Used as the div id
  # and as the scroll target after posting or editing.
  def anchor
    "c-#{path.tr('/', '-')}"
  end

  def author
    User.new("sub" => author_sub, "name" => author_name)
  end

  # This comment's reaction address (see Reaction / the reactions bar).
  def reaction_target
    "comment##{path}"
  end

  # The cache, cleaned for display: string emoji keys, positive counts only.
  def reaction_counts
    (reactions || {}).transform_keys(&:to_s).transform_values(&:to_i).select { |_e, n| n.positive? }
  end

  def deleted?
    !!deleted
  end

  # URL id for the edit/update/destroy routes. `path` contains "/", so it can't
  # be a raw route segment — encode it (the controller decodes).
  def to_param
    Base64.urlsafe_encode64(path)
  end

  # Does anything nest under this comment? A reply's path starts with mine + "/".
  def replies?
    Comment.where(post_id: post_id, "path.begins_with": "#{path}/").first.present?
  end

  # Remove this comment (and its reaction rows — cleared via BatchWriteItem). If it
  # has replies, soft-delete so the subtree stays threaded; otherwise delete it.
  def remove!
    Reaction.where(post_id: post_id, target: reaction_target).delete_all
    if replies?
      self.deleted = true
      self.body = nil
      self.reactions = {}
      save
    else
      delete
    end
  end

  private

  # Append a fresh time-ordered segment to the parent's path (or start a new path
  # when replying to the post). The segment is a zero-padded millisecond timestamp
  # plus random suffix, so it sorts chronologically and effectively never collides.
  def build_path
    segment = format("%013d-%s", (Time.now.to_f * 1000).to_i, SecureRandom.hex(3))
    self.path = parent_path.present? ? "#{parent_path}/#{segment}" : segment
  end
end
