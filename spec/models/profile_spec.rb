# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profile do
  it "is valid when blank (a fresh, unsaved profile)" do
    expect(Profile.new(sub: "dev|ada")).to be_valid
  end

  it "is valid with a display name and bio within the limits" do
    expect(Profile.new(sub: "dev|ada", display_name: "Ada", bio: "First programmer.")).to be_valid
  end

  it "rejects a display name longer than 60 characters" do
    expect(Profile.new(sub: "dev|ada", display_name: "x" * 61)).not_to be_valid
  end

  it "rejects a bio longer than 300 characters" do
    expect(Profile.new(sub: "dev|ada", bio: "x" * 301)).not_to be_valid
  end

  describe "#avatar_url" do
    it "is nil without an avatar_key" do
      expect(Profile.new(sub: "dev|ada").avatar_url).to be_nil
    end

    it "resolves an avatar_key to a media URL" do
      url = Profile.new(sub: "dev|ada", avatar_key: "uploads/dev_ada/a.jpg").avatar_url
      expect(url).to include("uploads/dev_ada/a.jpg")
    end
  end
end
