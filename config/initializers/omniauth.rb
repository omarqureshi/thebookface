# frozen_string_literal: true

# Authentication is Cognito over OIDC. Google is configured as a federated
# identity provider *inside* the Cognito user pool (see infra/), so the app only
# ever speaks OIDC to Cognito and never handles Google directly — Cognito is the
# system of record for users.
#
# All the Cognito coordinates arrive as env vars from the CDK stack. When they're
# absent (e.g. a bare local boot with no Cognito), we skip wiring the provider so
# the app still boots — the "Continue with Google" button just won't have a
# backend until you point it at a user pool.
if ENV["COGNITO_ISSUER"].present? && ENV["COGNITO_CLIENT_ID"].present?
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :openid_connect,
             name: :cognito,
             issuer: ENV["COGNITO_ISSUER"],
             discovery: true, # pull endpoints from Cognito's /.well-known/openid-configuration
             scope: %i[openid email profile],
             response_type: :code,
             # Skip Cognito's hosted-UI provider chooser and go straight to Google.
             extra_authorize_params: { identity_provider: "Google" },
             client_options: {
               identifier: ENV["COGNITO_CLIENT_ID"],
               secret: ENV["COGNITO_CLIENT_SECRET"],
               redirect_uri: ENV["COGNITO_REDIRECT_URI"]
             }
  end

  OmniAuth.config.allowed_request_methods = %i[post]
  OmniAuth.config.silence_get_warning = true
end
