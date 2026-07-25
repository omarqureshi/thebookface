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

  table name: ENV.fetch("COMMENTS_TABLE", "bookface-comments").to_sym, key: :post_id
  range :path # sort key — the materialized path

  # Set on a reply before save; blank means "reply to the post itself".
  field :parent_path
  field :author_sub
  field :author_name
  field :body

  # Denormalized reaction cache (see Post#reactions / Reaction.toggle).
  field :reactions, :raw, default: {}

  validates :body, presence: true, length: { maximum: 5_000 }
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

  private

  # Append a fresh time-ordered segment to the parent's path (or start a new path
  # when replying to the post). The segment is a zero-padded millisecond timestamp
  # plus random suffix, so it sorts chronologically and effectively never collides.
  def build_path
    segment = format("%013d-%s", (Time.now.to_f * 1000).to_i, SecureRandom.hex(3))
    self.path = parent_path.present? ? "#{parent_path}/#{segment}" : segment
  end
end
