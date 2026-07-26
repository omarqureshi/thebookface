require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Fatal only. The aws-sdk / Dynamoid request chatter and Rails' own request logs
  # all flow through this (tagged) logger, so a fatal level silences them — and
  # X-Ray active tracing still captures errors/faults. Set the level on the logger
  # explicitly too, because a custom-assigned logger doesn't reliably pick up
  # config.log_level. Override with RAILS_LOG_LEVEL when you need to debug.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "fatal")
  config.logger.level = config.log_level

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  # config.active_job.queue_adapter = :resque

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # Deployed behind CloudFront (which terminates TLS and redirects http→https),
  # so treat every request as SSL for secure cookies and HSTS.
  config.assume_ssl = true

  # The CDK hands the app its canonical public origin. CloudFront forwards the
  # Function URL's Host (the OAC signature is bound to it), so the app can't infer
  # its real host from the request — use APP_PUBLIC_URL for generated URLs.
  if (public_url = ENV["APP_PUBLIC_URL"]).present?
    uri = URI.parse(public_url)
    config.action_controller.default_url_options = { host: uri.host, protocol: uri.scheme }
  end
end
