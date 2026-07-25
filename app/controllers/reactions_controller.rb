# frozen_string_literal: true

class ReactionsController < ApplicationController
  before_action :require_login

  # Toggle the current user's single reaction on a target (the post, or a comment
  # addressed by "comment#<path>"). One entry point for add / switch / remove.
  def toggle
    post = Post.find(params[:post_id])
    Reaction.toggle(
      post_id: post.id,
      target: params.require(:target),
      user_sub: current_user.sub,
      emoji: params.require(:emoji)
    )
    redirect_back fallback_location: post_path(post)
  rescue ArgumentError
    redirect_back fallback_location: root_path, alert: "That reaction isn't allowed."
  rescue Dynamoid::Errors::RecordNotFound
    redirect_to root_path, alert: "That post no longer exists."
  end
end
