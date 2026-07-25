class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :signed_in?

  private

  def current_user
    @current_user ||= (User.new(session[:user]) if session[:user].present?)
  end

  def signed_in?
    current_user.present?
  end

  def require_login
    return if signed_in?

    redirect_to root_path, alert: "Please sign in with Google to do that."
  end
end
