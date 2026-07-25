# frozen_string_literal: true

class CommentsController < ApplicationController
  before_action :require_login

  def create
    @post = Post.find(params[:post_id])
    @comment = Comment.new(
      comment_params.to_h.symbolize_keys.merge(
        post_id: @post.id,
        author_sub: current_user.sub,
        author_name: current_user.name
      )
    )
    if @comment.save
      redirect_to post_path(@post, anchor: "c-#{@comment.path.tr('/', '-')}")
    else
      @comments = Comment.thread_for(@post.id)
      render "posts/show", status: :unprocessable_entity
    end
  rescue Dynamoid::Errors::RecordNotFound
    redirect_to root_path, alert: "That post no longer exists."
  end

  private

  # `parent_path` decides where the reply lands: blank = a top-level comment on
  # the post; otherwise the reply nests under the comment at that path.
  def comment_params
    params.require(:comment).permit(:body, :parent_path)
  end
end
