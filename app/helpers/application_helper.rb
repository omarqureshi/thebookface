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
end
