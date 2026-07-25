# frozen_string_literal: true

class SessionsController < ApplicationController
  # OmniAuth callback — the user has authenticated with Google via Cognito.
  def create
    auth = request.env["omniauth.auth"]
    user = User.new(
      "sub" => auth.uid,
      "email" => auth.info.email,
      "name" => auth.info.name
    )
    session[:user] = user.to_session
    redirect_to root_path, notice: "Signed in as #{user.name}."
  end

  # Clear our session, then the Cognito hosted-UI session so the next sign-in
  # actually re-prompts, then land back on the app.
  def destroy
    reset_session
    redirect_to cognito_logout_url, allow_other_host: true
  end

  def failure
    redirect_to root_path, alert: "Sign-in failed: #{params[:message] || 'unknown error'}."
  end

  # Fake sign-in (local dev + test) so the app is usable with no Cognito, and the
  # feature suite has a stubbed login. Guarded hard: nothing outside dev/test.
  def dev_create
    return head :forbidden unless Rails.env.local?

    key = params[:persona].to_s
    name = ApplicationHelper::DEV_PERSONAS.fetch(key, "Dev User")
    user = User.new("sub" => "dev|#{key.presence || 'user'}", "email" => "#{key.presence || 'dev'}@bookface.test", "name" => name)
    session[:user] = user.to_session
    redirect_to root_path, notice: "Signed in as #{name} (dev)."
  end

  private

  def cognito_logout_url
    domain = ENV["COGNITO_DOMAIN"]
    client = ENV["COGNITO_CLIENT_ID"]
    return root_path if domain.blank? || client.blank?

    "#{domain}/logout?client_id=#{client}&logout_uri=#{CGI.escape(root_url)}"
  end
end
