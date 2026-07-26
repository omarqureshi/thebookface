# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :require_login, only: %i[new create edit update destroy]
  before_action :load_and_authorize_post, only: %i[edit update destroy]

  def index
    @posts = Post.recent
    @post = Post.new
  end

  def show
    @post = Post.find(params[:id])
    @comment = Comment.new
    # The current user's own reactions across the whole thread ({ target =>
    # emoji }, one Query) for highlighting; {} when signed out. Counts come from
    # each item's cache, so this is the only extra read.
    @my_reactions = current_user&.reactions(@post) || {}
  rescue Dynamoid::Errors::RecordNotFound
    redirect_to root_path, alert: "That post no longer exists."
  end

  def new
    @post = Post.new
  end

  def create
    @post = Post.new(
      post_params.to_h.symbolize_keys.merge(
        author_sub: current_user.sub, author_name: current_user.name,
        media: AttachedMedia.from_params(params.dig(:post, :media_json), owner_sub: current_user.sub)
      )
    )
    if @post.save
      redirect_to @post, notice: "Posted to The Bookface."
    else
      @posts = Post.recent
      render :index, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @post.body = post_params[:body]
    if @post.save
      redirect_to @post, notice: "Post updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy_with_thread!
    redirect_to root_path, notice: "Post deleted."
  end

  private

  # Load a post for an owner-only action and authorize it. CanCanCan raises
  # AccessDenied for a non-owner; ApplicationController turns that into a bounce.
  def load_and_authorize_post
    @post = Post.find(params[:id])
    authorize!(action_name == "destroy" ? :destroy : :update, @post)
  rescue Dynamoid::Errors::RecordNotFound
    redirect_to root_path, alert: "That post no longer exists."
  end

  def post_params
    params.require(:post).permit(:body)
  end
end
