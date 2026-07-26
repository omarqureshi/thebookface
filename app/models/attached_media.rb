# frozen_string_literal: true

# The images a post is created with. The composer uploads straight to S3 and
# drops the resulting object keys into a hidden JSON field; this turns that
# untrusted blob into the `media` array a Post stores — parsed, filtered to keys
# the uploader actually owns (all presigning ever let them write), reduced to the
# fields we render, and capped at MAX. Malformed JSON yields nothing rather than
# raising, so a broken submission just posts without images.
class AttachedMedia
  MAX = 4 # images per post

  def self.from_params(media_json, owner_sub:)
    new(media_json, owner_sub).to_a
  end

  def initialize(media_json, owner_sub)
    @media_json = media_json
    @owner_sub = owner_sub
  end

  def to_a
    return [] if @media_json.blank?

    JSON.parse(@media_json).filter_map { |item| normalize(item) }.first(MAX)
  rescue JSON::ParserError, TypeError
    []
  end

  private

  # Keep a submitted item only if its key is under the owner's upload prefix,
  # reduced to the shape a Post stores.
  def normalize(item)
    key = item["key"].to_s
    return unless MediaStorage.owned_by?(key, @owner_sub)

    {
      "key" => key,
      "type" => "image",
      "content_type" => item["content_type"].to_s,
      "width" => item["width"].to_i,
      "height" => item["height"].to_i
    }
  end
end
