# frozen_string_literal: true

# The signed-in user's own profile. There's no :id and no ownership check to make
# — it always loads current_user's profile (keyed by their Cognito sub), so you
# can only ever see and edit your own.
class ProfilesController < ApplicationController
  before_action :require_login

  def show
    @profile = current_profile
  end

  def edit
    @profile = current_profile
  end

  def update
    @profile = current_profile
    @profile.display_name = profile_params[:display_name]
    @profile.bio = profile_params[:bio]
    @profile.avatar_key = accepted_avatar_key
    @profile.name = current_user.name # snapshot for the reconcile fallback
    if @profile.save
      ProfileReconciliation.enqueue(current_user.sub) # denormalized author fields, async
      redirect_to profile_path, notice: "Profile saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:profile).permit(:display_name, :bio, :avatar_key)
  end

  # The browser uploads the avatar straight to S3 and posts back its key. Trust
  # it only if it's under this user's own upload prefix (all presigning ever let
  # them write); otherwise keep the avatar they already had.
  def accepted_avatar_key
    key = profile_params[:avatar_key].to_s
    return @profile.avatar_key if key.blank?

    MediaStorage.owned_by?(key, current_user.sub) ? key : @profile.avatar_key
  end
end
