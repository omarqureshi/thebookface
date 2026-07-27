# frozen_string_literal: true

require "aws-cdk-lib"
require_relative "../config/environments"
require_relative "../support/dynamo_schema"

# The entire deployment for The Bookface, in Ruby. This is what you'd otherwise
# hand-write as a SAM/CloudFormation template — instead it's the CDK construct
# library, driven from Ruby via jsii:
#
#   * two DynamoDB tables — Posts, and a composite-key Comments table whose
#     (post_id, path) schema is exactly what the hierarchical-comment model needs;
#   * a Cognito user pool with Google wired in as a federated identity provider,
#     a hosted-UI domain, and an app client whose OAuth callback points back at
#     the app;
#   * the Rails app itself, packaged from the project's Dockerfile (Lamby), fronted
#     by a Lambda Function URL;
#   * least-privilege IAM, generated from the grants.
#
# The interesting bit is the wiring: the app client needs the app's URL (a
# Function URL, unknown until the function exists), and the function needs the
# client's id/secret — a cycle CDK lets us break by creating the URL first and
# calling `add_environment` afterwards.
class BookfaceStack < AWSCDK::Stack
  # CloudFront Function (viewer-request): 301 www.<domain> to the bare apex,
  # preserving path + query; non-www requests fall straight through. The
  # CloudFront Functions runtime is a constrained JS engine, so this stays ES5.
  WWW_REDIRECT_JS = <<~'JS'
    function handler(event) {
      var request = event.request;
      var host = request.headers.host ? request.headers.host.value : '';
      if (host.indexOf('www.') !== 0) {
        return request;
      }
      var apex = host.substring(4);
      var parts = [];
      for (var name in request.querystring) {
        var param = request.querystring[name];
        if (param.multiValue) {
          for (var i = 0; i < param.multiValue.length; i++) {
            parts.push(name + '=' + param.multiValue[i].value);
          }
        } else {
          parts.push(param.value === '' ? name : name + '=' + param.value);
        }
      }
      var query = parts.length ? '?' + parts.join('&') : '';
      return {
        statusCode: 301,
        statusDescription: 'Moved Permanently',
        headers: { location: { value: 'https://' + apex + request.uri + query } }
      };
    }
  JS

  def initialize(scope, id, env_name:, config:, **props)
    super(scope, id, props)

    @env_name = env_name
    @config = config
    @domain = config[:domain]
    # Data resources are torn down with the stack in dev/staging, retained in
    # prod. (auto_delete_objects can only accompany a DESTROY policy.)
    @removal_policy = config[:retain_data] ? AWSCDK::RemovalPolicy::RETAIN : AWSCDK::RemovalPolicy::DESTROY
    @auto_delete_objects = !config[:retain_data]

    # Each table's schema — keys and indexes — is read straight from its Dynamoid
    # model (see support/dynamo_schema.rb), so infra never restates what the app
    # already declares:
    #   * Posts, plus a by-recency GSI so the feed is one Query, not a Scan.
    #   * Comments: partitioned by post, sorted by the materialized `path`, so a
    #     Query returns the whole thread pre-ordered.
    #   * Reactions (one emoji per user per target): partitioned by post, sorted
    #     by "<user_sub>#<target>" so a user's reactions load in a single Query.
    posts     = DynamoSchema.table(self, "Posts", Post, removal_policy: @removal_policy)
    comments  = DynamoSchema.table(self, "Comments", Comment, removal_policy: @removal_policy)
    reactions = DynamoSchema.table(self, "Reactions", Reaction, removal_policy: @removal_policy)
    profiles  = DynamoSchema.table(self, "Profiles", Profile, removal_policy: @removal_policy)

    # Profile changes fan out to the denormalized author fields asynchronously: a
    # profile save drops the user's sub here, the Lambda consumes it (see the SQS
    # branch in LambdaHandler) and reconciles. Failures retry, then land in the DLQ.
    reconcile_dlq = AWSCDK::SQS::Queue.new(self, "ReconcileDLQ",
                                           { retention_period: AWSCDK::Duration.days(14) })
    reconcile_queue = AWSCDK::SQS::Queue.new(self, "ReconcileQueue", {
                                               visibility_timeout: AWSCDK::Duration.seconds(120),
                                               dead_letter_queue: { max_receive_count: 5, queue: reconcile_dlq }
                                             })

    # --- Media: private S3 bucket, browser-uploaded, CloudFront-served --------
    # Images are uploaded straight from the browser with presigned POSTs (bytes
    # never pass through Lambda). The bucket stays private; CloudFront serves it
    # via Origin Access Control.
    media = AWSCDK::S3::Bucket.new(
      self,
      "Media",
      {
        block_public_access: AWSCDK::S3::BlockPublicAccess.BLOCK_ALL,
        encryption: AWSCDK::S3::BucketEncryption::S3_MANAGED,
        removal_policy: @removal_policy,
        auto_delete_objects: @auto_delete_objects,
        cors: [
          {
            allowed_methods: [
              AWSCDK::S3::HttpMethods::POST,
              AWSCDK::S3::HttpMethods::PUT,
              AWSCDK::S3::HttpMethods::GET
            ],
            allowed_origins: ["*"], # demo; tighten to the app origin in production
            allowed_headers: ["*"],
            max_age: 3000
          }
        ]
      }
    )

    media_cdn = AWSCDK::CloudFront::Distribution.new(
      self,
      "MediaCdn",
      {
        default_behavior: {
          origin: AWSCDK::CloudFrontOrigins::S3BucketOrigin.with_origin_access_control(media),
          viewer_protocol_policy: AWSCDK::CloudFront::ViewerProtocolPolicy::REDIRECT_TO_HTTPS
        }
      }
    )

    # --- Cognito: users, with Google as the identity provider ----------------
    user_pool = AWSCDK::Cognito::UserPool.new(
      self,
      "Users",
      {
        # Users arrive by federating with Google, not by signing up directly.
        self_sign_up_enabled: false,
        sign_in_aliases: { email: true },
        removal_policy: @removal_policy
      }
    )

    # Real Google OAuth credentials are required to deploy. Supply them out of
    # band (never commit them): `-c google_client_id=… -c google_client_secret=…`
    # or GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET in the environment. Placeholders
    # let `cdk synth` still produce a template.
    google_client_id = node.try_get_context("google_client_id") || ENV["GOOGLE_CLIENT_ID"]
    google_client_secret = node.try_get_context("google_client_secret") || ENV["GOOGLE_CLIENT_SECRET"]
    if google_client_id.nil? || google_client_secret.nil?
      warn "[BookfaceStack] No Google OAuth credentials supplied — synthesising with " \
           "placeholders. Set -c google_client_id/-c google_client_secret (or " \
           "GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET) before deploying."
      google_client_id ||= "REPLACE_WITH_GOOGLE_CLIENT_ID"
      google_client_secret ||= "REPLACE_WITH_GOOGLE_CLIENT_SECRET"
    end

    google = AWSCDK::Cognito::UserPoolIdentityProviderGoogle.new(
      self,
      "Google",
      {
        user_pool: user_pool,
        client_id: google_client_id,
        client_secret_value: AWSCDK::SecretValue.unsafe_plain_text(google_client_secret),
        scopes: %w[openid email profile],
        # Map Google's profile onto the standard Cognito attributes.
        attribute_mapping: {
          email: AWSCDK::Cognito::ProviderAttribute.GOOGLE_EMAIL,
          given_name: AWSCDK::Cognito::ProviderAttribute.GOOGLE_GIVEN_NAME,
          family_name: AWSCDK::Cognito::ProviderAttribute.GOOGLE_FAMILY_NAME
        }
      }
    )

    # Hosted-UI domain (globally unique). Override the prefix with
    # `-c cognito_domain_prefix=…` if the default collides.
    domain_prefix = node.try_get_context("cognito_domain_prefix") || "the-bookface-#{@env_name}-#{account}"
    domain = AWSCDK::Cognito::UserPoolDomain.new(
      self,
      "HostedUI",
      {
        user_pool: user_pool,
        cognito_domain: { domain_prefix: domain_prefix }
      }
    )

    # --- The Rails app on Lambda (Lamby), fronted by a Function URL ----------
    rails = AWSCDK::Lambda::DockerImageFunction.new(
      self,
      "Rails",
      {
        code: AWSCDK::Lambda::DockerImageCode.from_image_asset(
          # Project root — where the Dockerfile lives (infra/stacks -> infra -> root).
          File.expand_path("../..", __dir__),
          # Declare the handler in ImageConfig rather than relying on the Dockerfile
          # CMD — real Lambda honours either, local emulators don't always.
          # BookfaceHandler routes HTTP events to Lamby and SQS events to the reconcile.
          { cmd: ["config/environment.BookfaceHandler.call"] }
        ),
        memory_size: @config[:memory_size],
        timeout: AWSCDK::Duration.seconds(60),
        # X-Ray active tracing: per-invocation traces (cold start, duration,
        # faults) + the service map. CDK adds the xray:Put* perms to the role.
        tracing: AWSCDK::Lambda::Tracing::ACTIVE,
        environment: {
          "RAILS_ENV" => "production",
          "BOOKFACE_ENV" => @env_name,
          # Rails serves /assets (and other public files) from the image. The app
          # is fronted by CloudFront with a cached, Brotli-compressed /assets/*
          # behavior (1-year TTL, digest-fingerprinted), so a given asset costs a
          # Lambda invocation at most once per edge per deploy.
          "RAILS_SERVE_STATIC_FILES" => "1",
          "POSTS_TABLE" => posts.table_name,
          "COMMENTS_TABLE" => comments.table_name,
          "REACTIONS_TABLE" => reactions.table_name,
          "PROFILES_TABLE" => profiles.table_name,
          "RECONCILE_QUEUE_URL" => reconcile_queue.queue_url,
          "MEDIA_BUCKET" => media.bucket_name,
          "MEDIA_PUBLIC_URL" => "https://#{media_cdn.distribution_domain_name}",
          # OIDC issuer for the user pool — the app discovers endpoints from here.
          "COGNITO_ISSUER" => "https://cognito-idp.#{region}.amazonaws.com/#{user_pool.user_pool_id}",
          "COGNITO_DOMAIN" => domain.base_url,
          # Supplied at deploy time as an env-scoped GitHub secret — no insecure
          # fallback, so a deploy without it fails fast. (Secrets Manager/SSM for
          # a production-grade setup.)
          "SECRET_KEY_BASE" => ENV.fetch("SECRET_KEY_BASE")
        }
      }
    )

    posts.grant_read_write_data(rails)
    comments.grant_read_write_data(rails)
    reactions.grant_read_write_data(rails)
    profiles.grant_read_write_data(rails)

    # The app enqueues reconcile messages; the same function consumes them (the
    # event source grants receive/delete + wires the trigger).
    reconcile_queue.grant_send_messages(rails)
    rails.add_event_source(AWSCDK::LambdaEventSources::SQSEventSource.new(reconcile_queue, { batch_size: 10 }))
    # Uploads are presigned (s3:PutObject); deleting a post also reaps its images
    # server-side (s3:DeleteObject). No read grant — CloudFront serves the bucket.
    media.grant_put(rails)
    media.grant_delete(rails)

    # Dynamoid checks table existence via dynamodb:ListTables on first write. It's
    # an account-level action with no resource-level scoping, so the per-table
    # grant_read_write_data above can't include it — grant it explicitly on "*".
    rails.add_to_role_policy(
      AWSCDK::IAM::PolicyStatement.new(
        { actions: ["dynamodb:ListTables"], resources: ["*"] }
      )
    )

    # A Function URL keeps the demo simple (Lamby speaks its payload format
    # natively). Its domain is unknown until now — which is why the app client's
    # callback URL and the function's Cognito env vars are wired up afterwards.
    # --- Public URL: a Function URL, optionally fronted by CloudFront ---------
    # A Function URL keeps the demo simple (Lamby speaks its payload format
    # natively) but can't carry a custom domain on its own. When one is
    # configured we front it with CloudFront: the Function URL is locked to
    # AWS_IAM and signed by an Origin Access Control, so only the distribution
    # can invoke it, and CloudFront terminates TLS for the domain. Without a
    # domain (before the zone exists, or a throwaway deploy) we fall back to the
    # raw public Function URL — the previous behaviour.
    custom_domain = !@domain.nil? && !Bookface::HOSTED_ZONE_ID.to_s.empty?

    # Public (NONE) even behind the custom domain. The "correct" hardening —
    # AWS_IAM + a CloudFront OAC signing the origin request — returned 403 from the
    # Function URL despite a textbook setup (auth type, resource policy, SourceArn,
    # OAC lambda/always/sigv4 all verified). Fronting a public Function URL with
    # CloudFront is the reliable path; the raw Function URL is therefore reachable
    # directly, which is acceptable for this demo. Revisit OAC hardening later.
    url = rails.add_function_url(
      { auth_type: AWSCDK::Lambda::FunctionURLAuthType::NONE }
    )

    app_base = custom_domain ? attach_custom_domain(url) : url.url

    client = AWSCDK::Cognito::UserPoolClient.new(
      self,
      "WebClient",
      {
        user_pool: user_pool,
        generate_secret: true,
        o_auth: {
          flows: { authorization_code_grant: true },
          scopes: [
            AWSCDK::Cognito::OAuthScope.OPENID,
            AWSCDK::Cognito::OAuthScope.EMAIL,
            AWSCDK::Cognito::OAuthScope.PROFILE
          ],
          callback_urls: ["#{app_base}auth/cognito/callback"],
          logout_urls: [app_base]
        },
        supported_identity_providers: [
          AWSCDK::Cognito::UserPoolClientIdentityProvider.GOOGLE
        ]
      }
    )
    # The client must not be created before the Google provider exists.
    client.node.add_dependency(google)

    # Break the cycle: now that the client (id + secret) and the public URL
    # exist, hand them to the already-created function.
    rails.add_environment("COGNITO_CLIENT_ID", client.user_pool_client_id)
    rails.add_environment("COGNITO_CLIENT_SECRET", client.user_pool_client_secret.unsafe_unwrap)
    rails.add_environment("COGNITO_REDIRECT_URI", "#{app_base}auth/cognito/callback")
    # Behind CloudFront the app is reached over HTTPS but the forwarded Host is
    # the Function URL's (OAC signs the origin request against that host, so the
    # viewer host can't also be forwarded). Hand the app its canonical origin so
    # generated URLs and cookies use the real domain.
    rails.add_environment("APP_PUBLIC_URL", app_base)

    AWSCDK::CfnOutput.new(self, "AppUrl", { value: app_base })
    AWSCDK::CfnOutput.new(self, "FunctionUrl", { value: url.url })
    # The generated function name, so the Run-task workflow can resolve which
    # Lambda to invoke for one-off tasks (rake/runner) without guessing.
    AWSCDK::CfnOutput.new(self, "FunctionName", { value: rails.function_name })
    AWSCDK::CfnOutput.new(self, "HostedUiDomain", { value: domain.base_url })
    AWSCDK::CfnOutput.new(self, "UserPoolId", { value: user_pool.user_pool_id })
    AWSCDK::CfnOutput.new(self, "MediaCdnUrl", { value: "https://#{media_cdn.distribution_domain_name}" })
  end

  # Front the Lambda Function URL with a CloudFront distribution on the
  # configured custom domain, aliased in Route 53, and return the app's public
  # base URL (trailing slash, matching FunctionUrl#url). The stack must be in
  # us-east-1 — CloudFront certificates live there.
  def attach_custom_domain(url)
    zone = AWSCDK::Route53::HostedZone.from_hosted_zone_attributes(
      self,
      "Zone",
      { hosted_zone_id: Bookface::HOSTED_ZONE_ID, zone_name: Bookface::HOSTED_ZONE_NAME }
    )

    # At the apex (prod) we also claim www and 301 it to the bare domain; a
    # subdomain env (staging) has no www.
    apex = @domain == Bookface::HOSTED_ZONE_NAME
    www  = apex ? "www.#{@domain}" : nil

    cert_props = {
      domain_name: @domain,
      validation: AWSCDK::CertificateManager::CertificateValidation.from_dns(zone)
    }
    cert_props[:subject_alternative_names] = [www] if www
    cert = AWSCDK::CertificateManager::Certificate.new(self, "AppCert", cert_props)

    # Function URL origin, reused across behaviours so CloudFront dedupes it. The
    # public Function URL requires its OWN host in the Host header, so CloudFront
    # can't forward the viewer host — which would otherwise leave Rails thinking its
    # host is the Lambda URL and building OAuth callbacks/redirects on it (breaking
    # sign-in with csrf_detected). Each stack serves exactly one domain, so tell the
    # app its real public host out-of-band via a static X-Forwarded-Host header;
    # Rails reads X-Forwarded-Host to compute request.host.
    origin = AWSCDK::CloudFrontOrigins::FunctionURLOrigin.new(
      url,
      { custom_headers: { "X-Forwarded-Host" => @domain } }
    )

    # www -> apex, as a viewer-request CloudFront Function: the 301 is returned
    # before the origin is ever hit, so a www request never costs a Lambda
    # invocation. It runs on every request; apex/staging traffic falls straight
    # through unchanged.
    fn_assoc =
      if www
        redirect = AWSCDK::CloudFront::Function.new(
          self,
          "WwwRedirect",
          {
            comment: "301 #{www} -> #{@domain}",
            runtime: AWSCDK::CloudFront::FunctionRuntime.JS_2_0,
            code: AWSCDK::CloudFront::FunctionCode.from_inline(WWW_REDIRECT_JS)
          }
        )
        [{ function: redirect, event_type: AWSCDK::CloudFront::FunctionEventType::VIEWER_REQUEST }]
      end

    # Forward everything the app needs (all cookies + query strings) but drop three
    # headers: `host` (the public Function URL requires its own host in Host, so the
    # viewer host can't be forwarded), `x-forwarded-host` (so a viewer can't spoof
    # the real host that the origin's custom header injects), and `authorization`
    # (this cookie-auth app never uses it).
    app_origin_request_policy = AWSCDK::CloudFront::OriginRequestPolicy.new(
      self,
      "AppOriginRequestPolicy",
      {
        cookie_behavior: AWSCDK::CloudFront::OriginRequestCookieBehavior.all,
        query_string_behavior: AWSCDK::CloudFront::OriginRequestQueryStringBehavior.all,
        header_behavior: AWSCDK::CloudFront::OriginRequestHeaderBehavior.deny_list("host", "x-forwarded-host", "authorization")
      }
    )

    default_behavior = {
      origin: origin,
      viewer_protocol_policy: AWSCDK::CloudFront::ViewerProtocolPolicy::REDIRECT_TO_HTTPS,
      # A dynamic Rails app: cache nothing by default; forward what it needs via
      # the custom policy above (host/authorization dropped for OAC signing).
      allowed_methods: AWSCDK::CloudFront::AllowedMethods.ALLOW_ALL,
      cache_policy: AWSCDK::CloudFront::CachePolicy.CACHING_DISABLED,
      origin_request_policy: app_origin_request_policy
    }
    # Static assets are served straight from S3 — the deploy uploads the image's
    # own precompiled, digest-stamped assets, so an asset never reaches the Lambda
    # even on a cache miss. The bucket is private; CloudFront reads it via Origin
    # Access Control. Digest-stamped means immutable, so cache hard at the edge.
    assets_bucket = AWSCDK::S3::Bucket.new(
      self,
      "Assets",
      {
        block_public_access: AWSCDK::S3::BlockPublicAccess.BLOCK_ALL,
        encryption: AWSCDK::S3::BucketEncryption::S3_MANAGED,
        removal_policy: @removal_policy,
        auto_delete_objects: @auto_delete_objects
      }
    )
    AWSCDK::CfnOutput.new(self, "AssetsBucket", { value: assets_bucket.bucket_name })

    assets_behavior = {
      origin: AWSCDK::CloudFrontOrigins::S3BucketOrigin.with_origin_access_control(assets_bucket),
      viewer_protocol_policy: AWSCDK::CloudFront::ViewerProtocolPolicy::REDIRECT_TO_HTTPS,
      cache_policy: AWSCDK::CloudFront::CachePolicy.CACHING_OPTIMIZED
    }
    if fn_assoc
      default_behavior[:function_associations] = fn_assoc
      assets_behavior[:function_associations] = fn_assoc
    end

    app_cdn = AWSCDK::CloudFront::Distribution.new(
      self,
      "AppCdn",
      {
        domain_names: www ? [@domain, www] : [@domain],
        certificate: cert,
        default_behavior: default_behavior,
        additional_behaviors: { "/assets/*" => assets_behavior }
      }
    )

    # Alias the domain(s) at the distribution (A + AAAA, for IPv4 and IPv6).
    # record_name is relative to the zone root — nil at the apex (prod), the
    # label ("staging") otherwise; "www" gets its own pair at the apex.
    alias_target = AWSCDK::Route53::RecordTarget.from_alias(
      AWSCDK::Route53Targets::CloudFrontTarget.new(app_cdn)
    )
    record_name = apex ? nil : @domain.sub(/\.#{Regexp.escape(Bookface::HOSTED_ZONE_NAME)}\z/, "")
    AWSCDK::Route53::ARecord.new(self, "AppAliasA", { zone: zone, record_name: record_name, target: alias_target })
    AWSCDK::Route53::AaaaRecord.new(self, "AppAliasAaaa", { zone: zone, record_name: record_name, target: alias_target })
    if www
      AWSCDK::Route53::ARecord.new(self, "WwwAliasA", { zone: zone, record_name: "www", target: alias_target })
      AWSCDK::Route53::AaaaRecord.new(self, "WwwAliasAaaa", { zone: zone, record_name: "www", target: alias_target })
    end

    "https://#{@domain}/"
  end
end
