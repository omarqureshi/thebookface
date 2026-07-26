# frozen_string_literal: true

# A user's single reaction (one emoji) on a post or comment — Facebook-style.
# This table is the source of truth; each Post/Comment also carries a
# denormalized {emoji => count} cache (its `reactions` field) so rendering counts
# never reads this table. The two are kept in step with a single
# TransactWriteItems, so they can't diverge.
#
# Keying: partition by post, sort by "<user_sub>#<target>", where target is
# "post" or "comment#<path>". So (a) a user has at most one reaction per target
# (the key is unique; `emoji` is a replaceable attribute), and (b) a user's
# reactions across a whole thread load in one Query (begins_with "<user_sub>#").
class Reaction
  include Dynamoid::Document

  table name: Rails.application.config.x.dynamodb.reactions_table.to_sym, key: :post_id
  range :sk

  field :emoji
  field :user_sub
  field :target

  # The reaction palette. 👍/👎 are just two of them; a net "like score" is
  # count("👍") − count("👎") if you ever want one.
  PALETTE = %w[👍 👎 ❤️ 😂 😮 😢 😡].freeze

  class << self
    def sk_for(user_sub, target)
      "#{user_sub}##{target}"
    end

    # A user's own reactions across a post (the post + all its comments), as
    # { target => emoji } — one Query.
    def mine_for_post(post_id, user_sub)
      where(post_id: post_id, "sk.begins_with": "#{user_sub}#")
        .each_with_object({}) { |r, acc| acc[r.target] = r.emoji }
    end

    # Toggle user_sub's reaction on a target to `emoji`:
    #   no current reaction        -> add it
    #   current reaction == emoji  -> remove it (toggle off)
    #   current reaction != emoji  -> switch to the new emoji
    # Returns the resulting emoji (or nil if toggled off). The per-user item and
    # the target's count cache move together; a condition on the previous emoji
    # makes a concurrent change fail the transaction, which we retry once.
    def toggle(post_id:, target:, user_sub:, emoji:)
      raise ArgumentError, "unknown emoji" unless PALETTE.include?(emoji)

      2.times do
        current = current_emoji(post_id, user_sub, target)
        resulting = (current == emoji ? nil : emoji)
        return nil if current.nil? && resulting.nil?

        begin
          write!(post_id: post_id, target: target, user_sub: user_sub,
                 old_emoji: current, new_emoji: resulting)
          return resulting
        rescue Aws::DynamoDB::Errors::TransactionCanceledException
          next # lost a race — re-read and try once more
        end
      end
      raise Dynamoid::Errors::Error, "reaction toggle kept losing a race"
    end

    private

    def current_emoji(post_id, user_sub, target)
      where(post_id: post_id, sk: sk_for(user_sub, target)).first&.emoji
    end

    # The (table, key) of the item that carries the count cache for a target.
    def target_ref(post_id, target)
      if target == "post"
        [Post.table_name.to_s, { "id" => post_id }]
      elsif target.start_with?("comment#")
        [Comment.table_name.to_s, { "post_id" => post_id, "path" => target.delete_prefix("comment#") }]
      else
        raise ArgumentError, "unknown target #{target.inspect}"
      end
    end

    # Both writes commit atomically via a DynamoDB transaction. We drop to the
    # raw client rather than Dynamoid's `Model.transaction` DSL on purpose — the
    # DSL can't express either op here:
    #   * The count cache is an atomic `ADD reactions.<emoji> :delta` on a nested
    #     map key. Dynamoid's transactional increment (ItemUpdater) only accepts
    #     declared top-level attributes, so it can't target `reactions.<emoji>`.
    #   * The reaction item is written conditionally on its *prior* value
    #     (`emoji = :old`, and a conditional delete), beyond the DSL's built-in
    #     attribute_exists/not_exists conditions.
    # And a `Model.transaction` block only takes DSL ops, so one raw op forces the
    # whole transaction raw. Don't "clean this up" into the DSL — it can't do it.
    def write!(post_id:, target:, user_sub:, old_emoji:, new_emoji:)
      client = Dynamoid.adapter.client
      sk = sk_for(user_sub, target)

      # 1. The per-user reaction item (source of truth).
      item_op =
        if old_emoji.nil?
          { put: {
            table_name: table_name.to_s,
            item: { "post_id" => post_id, "sk" => sk, "emoji" => new_emoji,
                    "user_sub" => user_sub, "target" => target },
            condition_expression: "attribute_not_exists(post_id)"
          } }
        elsif new_emoji.nil?
          { delete: {
            table_name: table_name.to_s,
            key: { "post_id" => post_id, "sk" => sk },
            condition_expression: "emoji = :old",
            expression_attribute_values: { ":old" => old_emoji }
          } }
        else
          { update: {
            table_name: table_name.to_s,
            key: { "post_id" => post_id, "sk" => sk },
            update_expression: "SET emoji = :new",
            condition_expression: "emoji = :old",
            expression_attribute_values: { ":new" => new_emoji, ":old" => old_emoji }
          } }
        end

      # 2. The target's count cache: atomic ADD of the deltas.
      deltas = Hash.new(0)
      deltas[old_emoji] -= 1 if old_emoji
      deltas[new_emoji] += 1 if new_emoji
      names = {}
      values = {}
      adds = deltas.each_with_index.map do |(e, d), i|
        names["#e#{i}"] = e
        values[":d#{i}"] = d
        "reactions.#e#{i} :d#{i}"
      end
      cache_table, cache_key = target_ref(post_id, target)
      cache_op = { update: {
        table_name: cache_table,
        key: cache_key,
        update_expression: "ADD #{adds.join(', ')}",
        expression_attribute_names: names,
        expression_attribute_values: values
      } }

      client.transact_write_items(transact_items: [item_op, cache_op])
    end
  end
end
