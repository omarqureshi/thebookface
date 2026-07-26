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
    if @profile.save
      redirect_to profile_path, notice: "Profile saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:profile).permit(:display_name, :bio)
  end
end
