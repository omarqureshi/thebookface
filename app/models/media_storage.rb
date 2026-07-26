# frozen_string_literal: true

require "aws-sdk-s3"

# Images live in S3. The browser uploads straight to S3 with a presigned POST —
# bytes never pass through the Rails/Lambda app — and the post record stores only
# the object key. Served via CloudFront in production; MinIO stands in for S3
# locally (endpoint via MEDIA_ENDPOINT).
module MediaStorage
  MAX_BYTES = 15 * 1024 * 1024

  ALLOWED_TYPES = {
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/gif" => ".gif",
    "image/webp" => ".webp"
  }.freeze

  module_function

  def bucket = ENV.fetch("MEDIA_BUCKET", "bookface-media")
  def region = ENV.fetch("AWS_REGION", "us-east-1")

  # MinIO stands in for S3 in local dev/test (see compose.yaml), so it's the
  # default endpoint there — `bin/rails server` needs no media env vars. nil in
  # production => the real S3 service with the Lambda role.
  def endpoint
    ENV["MEDIA_ENDPOINT"].presence || (Rails.env.local? ? "http://localhost:9000" : nil)
  end

  def allowed_type?(content_type) = ALLOWED_TYPES.key?(content_type)

  # A URL-safe upload prefix for a user (Cognito subs are UUIDs; dev personas
  # carry a "|", so normalise).
  def prefix_for(user_sub)
    "uploads/#{user_sub.to_s.gsub(/[^a-zA-Z0-9_-]/, '_')}"
  end

  # Presigned POST for a browser upload, scoped to this user's prefix so they
  # can only ever write their own objects.
  def presigned_upload(user_sub:, content_type:)
    key = "#{prefix_for(user_sub)}/#{SecureRandom.uuid}#{ALLOWED_TYPES.fetch(content_type)}"
    post = Aws::S3::PresignedPost.new(
      credentials, region, bucket,
      key: key,
      content_type: content_type,
      content_length_range: 1..MAX_BYTES,
      success_action_status: "201",
      signature_expiration: Time.now + 300,
      url: upload_url
    )
    { url: post.url, fields: post.fields, key: key }
  end

  # Public URL for serving (CloudFront in prod; MinIO's public path in dev/test).
  def public_url(key)
    base = ENV["MEDIA_PUBLIC_URL"].presence
    base ||= "http://localhost:9000/#{bucket}" if Rails.env.local?
    "#{base || upload_url}/#{key}"
  end

  # A key belongs to this user only if it sits under their upload prefix — the
  # only place presigning ever let them write.
  def owned_by?(key, user_sub)
    key.to_s.start_with?("#{prefix_for(user_sub)}/")
  end

  # Reap objects from S3 in one DeleteObjects call per 1000 keys (the S3 analog
  # of BatchWriteItem — not one DeleteObject per key). Best-effort: the caller
  # has already removed the DynamoDB record, so an S3 error must not raise and
  # leave a half-deleted post — orphaned bytes are a recoverable cost, so log and
  # move on.
  def delete_objects(keys)
    keys = Array(keys).map(&:to_s).reject(&:empty?).uniq
    return if keys.empty?

    keys.each_slice(1000) do |batch|
      client.delete_objects(
        bucket: bucket,
        delete: { objects: batch.map { |k| { key: k } }, quiet: true }
      )
    end
  rescue Aws::S3::Errors::ServiceError, Seahorse::Client::NetworkingError => e
    Rails.logger.error("MediaStorage#delete_objects left #{keys.size} object(s): #{e.class}: #{e.message}")
  end

  # --- internals ---

  # An S3 client for server-side operations (presigning needs none). Path-style
  # against MinIO in dev/test; the Lambda role's creds + virtual-host S3 in prod.
  def client
    opts = { region: region }
    if endpoint
      opts.merge!(endpoint: endpoint, force_path_style: true, credentials: credentials)
    end
    Aws::S3::Client.new(**opts)
  end

  def upload_url
    if endpoint
      "#{endpoint}/#{bucket}" # path-style (MinIO)
    else
      "https://#{bucket}.s3.#{region}.amazonaws.com" # virtual-host (S3)
    end
  end

  def credentials
    if endpoint
      Aws::Credentials.new(
        ENV.fetch("MEDIA_ACCESS_KEY_ID", "minioadmin"),
        ENV.fetch("MEDIA_SECRET_ACCESS_KEY", "minioadmin")
      )
    else
      # On Lambda, the function role's credentials (resolved from the default chain).
      Aws::CredentialProviderChain.new.resolve.credentials
    end
  end
end
