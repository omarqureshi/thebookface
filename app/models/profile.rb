# frozen_string_literal: true

# A user's editable profile. Cognito owns identity (login and the stable `sub`);
# this table owns the domain bits the app lets people change — a display name, a
# short bio, and an avatar (an S3 key, uploaded through the same presigned flow
# as post media). Keyed by the Cognito `sub`, so there's exactly one profile per
# user, found in a single GetItem.
class Profile
  include Dynamoid::Document

  table name: Rails.application.config.x.dynamodb.profiles_table.to_sym, key: :sub

  field :display_name
  field :bio
  field :avatar_key

  validates :display_name, length: { maximum: 60 }
  validates :bio, length: { maximum: 300 }

  # This user's profile, or a fresh blank one to fill in — never raises for a
  # first-time user who hasn't saved anything yet.
  def self.for(sub)
    find(sub, raise_error: false) || new(sub: sub)
  end

  # Public (CloudFront / MinIO) URL of the avatar, or nil when none is set.
  def avatar_url
    MediaStorage.public_url(avatar_key) if avatar_key.present?
  end
end
