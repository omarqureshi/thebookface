# frozen_string_literal: true

class UploadsController < ApplicationController
  before_action :require_login

  # Hand the browser a presigned POST so it can upload one image straight to S3.
  # Scoped to the current user's prefix — they can only ever write their own keys.
  def create
    content_type = params.require(:content_type)
    unless MediaStorage.allowed_type?(content_type)
      return render json: { error: "unsupported type" }, status: :unprocessable_entity
    end

    render json: MediaStorage.presigned_upload(user_sub: current_user.sub, content_type: content_type)
  end
end
