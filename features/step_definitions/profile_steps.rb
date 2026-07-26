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
