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
    @comments = Comment.thread_for(@post.id) # pre-ordered thread, one Query
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
        author_sub: current_user.sub, author_name: current_user.name, media: accepted_media
      )
    )
    if @post.body.present? || @post.media.present?
      if @post.save
        return redirect_to @post, notice: "Posted to The Bookface."
      end
    else
      @post.errors.add(:base, "Add something to say or a photo.")
    end
    @posts = Post.recent
    render :index, status: :unprocessable_entity
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

  # The composer's uploader dropped S3 keys into a hidden JSON field. Trust only
  # keys under the current user's own upload prefix (that's all presigning let
  # them write), and keep just the fields we render.
  def accepted_media
    raw = params.dig(:post, :media_json)
    return [] if raw.blank?

    JSON.parse(raw).filter_map do |m|
      key = m["key"].to_s
      next unless MediaStorage.owned_by?(key, current_user.sub)

      {
        "key" => key,
        "type" => "image",
        "content_type" => m["content_type"].to_s,
        "width" => m["width"].to_i,
        "height" => m["height"].to_i
      }
    end.first(4)
  rescue JSON::ParserError, TypeError
    []
  end
end
