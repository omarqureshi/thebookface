# frozen_string_literal: true

require "rails_helper"

RSpec.describe AttachedMedia do
  let(:owner) { "dev|ada" }
  # A key under the owner's presign prefix (see MediaStorage.prefix_for).
  def owned_key(name = "1.jpg") = "uploads/dev_ada/#{name}"

  def parse(items)
    described_class.from_params(items.to_json, owner_sub: owner)
  end

  it "is empty for blank or nil input" do
    expect(described_class.from_params(nil, owner_sub: owner)).to eq([])
    expect(described_class.from_params("", owner_sub: owner)).to eq([])
  end

  it "is empty (not raising) for malformed JSON" do
    expect(described_class.from_params("{not json", owner_sub: owner)).to eq([])
  end

  it "normalizes an owned item to the stored shape" do
    result = parse([{ "key" => owned_key, "content_type" => "image/jpeg", "width" => 120, "height" => 90 }])
    expect(result).to eq([
      { "key" => owned_key, "type" => "image", "content_type" => "image/jpeg", "width" => 120, "height" => 90 }
    ])
  end

  it "drops keys the user does not own" do
    result = parse([{ "key" => "uploads/dev_grace/secret.jpg", "content_type" => "image/png" }])
    expect(result).to eq([])
  end

  it "coerces width/height to integers and content_type to a string" do
    result = parse([{ "key" => owned_key, "content_type" => nil, "width" => "120", "height" => nil }])
    expect(result.first).to include("content_type" => "", "width" => 120, "height" => 0)
  end

  it "caps the number of images at MAX" do
    many = Array.new(AttachedMedia::MAX + 3) { |i| { "key" => owned_key("#{i}.jpg") } }
    expect(parse(many).size).to eq(AttachedMedia::MAX)
  end
end
