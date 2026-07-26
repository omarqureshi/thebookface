class ApplicationController < ActionController::Base
  # authorize! / can? / current_ability. CanCanCan usually auto-includes this into
  # ActionController::Base, but include it explicitly so it can't silently go
  # missing (a double include is a no-op).
  include CanCan::ControllerAdditions

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :signed_in?, :current_profile

  # Authorization failures (CanCanCan) → a friendly bounce, not a 500. CanCanCan's
  # current_ability uses current_user (below) to build Ability.new(current_user).
  rescue_from CanCan::AccessDenied do |_exception|
    redirect_back fallback_location: root_path,
                  alert: "You can only edit or delete your own posts and comments."
  end

  private

  def current_user
    @current_user ||= (User.new(session[:user]) if session[:user].present?)
  end

  # The signed-in user's profile (display name / bio / avatar) — a fresh blank
  # one until they save. Cognito claims (current_user) are identity; this is the
  # editable layer on top.
  def current_profile
    @current_profile ||= Profile.for(current_user.sub) if current_user
  end

  # The author snapshot stamped onto a new post/comment: who wrote it plus their
  # current display name + avatar, denormalized for cheap feed reads and kept in
  # step afterwards by the profile reconcile job.
  def author_attributes
    {
      author_sub: current_user.sub,
      author_name: current_profile.display_name.presence || current_user.name,
      author_avatar: current_profile.avatar_key
    }
  end

  def signed_in?
    current_user.present?
  end

  def require_login
    return if signed_in?

    redirect_to root_path, alert: "Please sign in with Google to do that."
  end
end
