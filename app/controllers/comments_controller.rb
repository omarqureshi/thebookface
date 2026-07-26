# frozen_string_literal: true

class CommentsController < ApplicationController
  before_action :require_login
  before_action :load_and_authorize_comment, only: %i[update destroy]

  def create
    @post = Post.find(params[:post_id])
    @comment = Comment.new(
      comment_params.to_h.symbolize_keys.merge(
        { post_id: @post.id }, author_attributes
      )
    )
    if @comment.save
      redirect_to post_path(@post, anchor: @comment.anchor)
    else
      # Re-rendering the post page needs the same setup the show action does.
      @my_reactions = current_user&.reactions(@post) || {}
      render "posts/show", status: :unprocessable_entity
    end
  rescue Dynamoid::Errors::RecordNotFound
    redirect_to root_path, alert: "That post no longer exists."
  end

  def update
    @comment.body = comment_params[:body]
    if @comment.save
      redirect_to post_path(@post, anchor: @comment.anchor), notice: "Comment updated."
    else
      redirect_to post_path(@post), alert: "A comment can't be empty."
    end
  end

  def destroy
    @comment.remove!
    redirect_to post_path(@post), notice: "Comment removed."
  end

  private

  # Load a comment for an owner-only action and authorize it. The route id is the
  # URL-safe-encoded path (see Comment#to_param), because the path contains "/".
  def load_and_authorize_comment
    @post = Post.find(params[:post_id])
    @comment = Comment.find(@post.id, range_key: Base64.urlsafe_decode64(params[:id]))
    authorize!(action_name == "destroy" ? :destroy : :update, @comment)
  rescue Dynamoid::Errors::RecordNotFound, ArgumentError
    redirect_to root_path, alert: "That comment no longer exists."
  end

  # `parent_path` decides where the reply lands: blank = a top-level comment on
  # the post; otherwise the reply nests under the comment at that path.
  def comment_params
    params.require(:comment).permit(:body, :parent_path)
  end
end
