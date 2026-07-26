# frozen_string_literal: true

When("I open my profile") do
  visit profile_path
end

When("I open the feed") do
  visit root_path
end

When("I set my display name to {string} and bio {string}") do |name, bio|
  visit edit_profile_path
  fill_in "profile[display_name]", with: name
  fill_in "profile[bio]", with: bio
  click_button "Save"
end

# The browser JS uploads to S3 and fills this hidden field; under rack_test we set
# the (owned) key directly to exercise the server side.
When("I set my avatar to an image I uploaded") do
  visit edit_profile_path
  key = "#{MediaStorage.prefix_for(persona_sub('Ada Lovelace'))}/avatar.jpg"
  find("input[name='profile[avatar_key]']", visible: :all).set(key)
  click_button "Save"
end

When("I try to set my avatar to someone else's key") do
  visit edit_profile_path
  find("input[name='profile[avatar_key]']", visible: :all).set("uploads/dev_grace/stolen.jpg")
  click_button "Save"
end

Then("my profile shows my photo") do
  expect(page).to have_css(".avatar--photo")
end

Then("my profile has no photo") do
  expect(page).to have_no_css(".avatar--photo")
end
