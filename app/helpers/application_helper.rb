module ApplicationHelper
  # Cognito is wired up (deployed / configured) when its issuer is present.
  def cognito_configured?
    ENV["COGNITO_ISSUER"].present?
  end

  # In local dev/test with no Cognito, offer a fake sign-in so the app is fully
  # usable under pure Puma — no Lambda, no Google, no user pool required. It's
  # also the "stubbed login" the feature tests drive.
  def dev_auth?
    Rails.env.local? && !cognito_configured?
  end

  # A few personas for the dev sign-in, so you can test multi-author comment
  # threads locally.
  DEV_PERSONAS = {
    "ada" => "Ada Lovelace",
    "grace" => "Grace Hopper",
    "alan" => "Alan Turing"
  }.freeze

  # Public (CloudFront / MinIO) URL for a media object key.
  def media_url(key)
    MediaStorage.public_url(key)
  end

  # The signed-in user's avatar — their uploaded photo if set, else their
  # initials on the usual gradient. `extra` adds modifiers (e.g. "avatar--lg").
  def current_avatar(extra = nil)
    classes = ["avatar", extra].compact.join(" ")
    if (url = current_profile&.avatar_url)
      tag.span("", class: "#{classes} avatar--photo", style: "background-image: url(#{url})")
    else
      tag.span(current_user.initials, class: classes)
    end
  end

  # Avatar for a post/comment author, from the denormalized snapshot on the
  # record — the photo if there's an avatar key, else initials from the name.
  def author_avatar_tag(record, extra = nil)
    classes = ["avatar", extra].compact.join(" ")
    if record.author_avatar.present?
      tag.span("", class: "#{classes} avatar--photo",
               style: "background-image: url(#{media_url(record.author_avatar)})")
    else
      tag.span(record.author.initials, class: classes)
    end
  end

  # Stable DOM id for a subject's reactions bar, so a reaction toggle can swap
  # just that bar via Turbo Stream (the post, or a specific comment).
  def reactions_dom_id(post, subject)
    "reactions-#{post.id}-#{subject.reaction_target.gsub(/[^0-9a-z]+/i, '-')}"
  end
end
