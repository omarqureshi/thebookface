# frozen_string_literal: true

module Bookface
  # The registered domain (bought via Route 53). One public hosted zone covers
  # every environment — prod at the apex, staging at a subdomain. thebookface.net
  # is registered, so its zone id is the default below; override with
  # BOOKFACE_HOSTED_ZONE_ID (or set that empty to force the raw-Function-URL
  # fallback — e.g. a throwaway deploy in another account before its zone exists).
  HOSTED_ZONE_NAME = "thebookface.net"
  HOSTED_ZONE_ID   = ENV["BOOKFACE_HOSTED_ZONE_ID"] || "Z0430301186RRIJICRS18"

  # Per-environment deployment config. Each environment becomes its own stack
  # (TheBookface-staging / -prod). There is no dev environment — local work runs
  # on plain Puma (see the app README), so staging is the lowest deployed tier.
  #
  # account/region default to the CDK environment (CDK_DEFAULT_ACCOUNT / REGION)
  # when nil — so a single-account demo can deploy every environment into one
  # account under distinct stack names, while a real setup points each at its own
  # account via BOOKFACE_<ENV>_ACCOUNT. No Control Tower required: these are just
  # separate stacks.
  #
  # NOTE: a custom-domain stack terminates TLS at CloudFront, whose ACM cert must
  # live in us-east-1 — so leave region at the us-east-1 default unless you also
  # arrange a us-east-1 certificate yourself.
  ENVIRONMENTS = {
    "staging" => {
      account: ENV["BOOKFACE_STAGING_ACCOUNT"],
      region: ENV["BOOKFACE_STAGING_REGION"],
      retain_data: false, # tear tables/bucket down with the stack
      memory_size: 1024,
      # Moved aside so the bookface-rpc (Foobara) stack can take
      # staging.thebookface.net: CloudFront will not serve one alternate domain
      # name from two distributions.
      #
      # Renamed rather than set to nil. The nil path — the raw Function URL —
      # looks like the obvious way to release a name, but it does not deploy:
      # app_base then becomes the Function URL attribute, which the Cognito
      # client's callback depends on, while the function depends on the client's
      # id and secret. CloudFormation rejects the cycle. That fallback predates
      # the Cognito wiring and has not been exercised since.
      domain: "rails-staging.#{HOSTED_ZONE_NAME}"
    },
    "prod" => {
      account: ENV["BOOKFACE_PROD_ACCOUNT"],
      region: ENV["BOOKFACE_PROD_REGION"],
      retain_data: true,  # protect data if the stack is deleted
      memory_size: 1769,  # ~1 vCPU
      domain: HOSTED_ZONE_NAME
    }
  }.freeze
end
