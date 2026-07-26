# frozen_string_literal: true

require "rails_helper"

RSpec.describe Post do
  # The smallest set of attributes that make a Post valid — tweak per example.
  def build(**overrides)
    Post.new({ author_sub: "dev|ada", author_name: "Ada", body: "hello" }.merge(overrides))
  end

  it "is valid with a body and no media" do
    expect(build).to be_valid
  end

  it "is valid with media and no body (an image-only post)" do
    post = build(body: nil, media: [{ "key" => "uploads/dev_ada/1.jpg" }])
    expect(post).to be_valid
  end

  it "is invalid with neither a body nor media" do
    post = build(body: nil, media: [])
    expect(post).not_to be_valid
    expect(post.errors.full_messages).to include("Add something to say or a photo.")
  end

  it "treats a blank body as no body" do
    expect(build(body: "   ", media: [])).not_to be_valid
  end

  it "is invalid without an author" do
    expect(build(author_sub: nil)).not_to be_valid
  end

  it "is valid at the 5000-character body limit" do
    expect(build(body: "x" * 5_000)).to be_valid
  end

  it "is invalid past the 5000-character body limit" do
    expect(build(body: "x" * 5_001)).not_to be_valid
  end
end
