# frozen_string_literal: true

class ReactionsController < ApplicationController
  before_action :require_login

  # Toggle the current user's single reaction on a target (the post, or a comment
  # addressed by "comment#<path>"). One entry point for add / switch / remove.
  # Responds with a Turbo Stream that swaps just this subject's reactions bar, so
  # reacting is an XHR update rather than a full page reload (plain-HTML fallback
  # redirects back).
  def toggle
    post = Post.find(params[:post_id])
    target = params.require(:target)
    Reaction.toggle(
      post_id: post.id,
      target: target,
      user_sub: current_user.sub,
      emoji: params.require(:emoji)
    )

    subject = reaction_subject(post, target)
    mine = current_user.reactions(post)[target]

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          helpers.reactions_dom_id(post, subject),
          partial: "reactions/bar",
          locals: { post: post, subject: subject, mine: mine }
        )
      end
      format.html { redirect_back fallback_location: post_path(post) }
    end
  rescue ArgumentError
    redirect_back fallback_location: root_path, alert: "That reaction isn't allowed."
  rescue Dynamoid::Errors::RecordNotFound
    redirect_to root_path, alert: "That post no longer exists."
  end

  private

  # Reload the reaction's subject so its cached counts are fresh: the post itself,
  # or the comment addressed by "comment#<materialized-path>".
  def reaction_subject(post, target)
    return Post.find(post.id) if target == "post"

    Comment.find(post.id, range_key: target.delete_prefix("comment#"))
  end
end
