# frozen_string_literal: true

# Steps for the emoji reactions bar. A reaction is a button_to in the palette;
# under rack_test clicking it submits the form and the controller redirects back
# (the Turbo-Stream swap is the browser path), so the reloaded page shows the
# updated counts.

When("I react {string} to the post") do |emoji|
  within(".post .reactions__palette") { click_button emoji }
end

When("I react {string} to the comment {string}") do |emoji, body|
  within find(".comment", text: body, match: :prefer_exact) do
    within(".reactions__palette") { click_button emoji }
  end
end

Then("the post has no reaction counts") do
  within(".post") { expect(page).to have_no_css(".reactions__counts") }
end
