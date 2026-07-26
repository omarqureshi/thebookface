# frozen_string_literal: true

# Steps for editing/deleting your own content and being refused someone else's.
# Ownership hinges on author_sub == current_user.sub, so "my" seeds use
# persona_sub(@me) (the "dev|<key>" the stubbed sign-in sets), while the shared
# "a post by …"/"has a comment …" seeds use a "seed|…" sub that no persona owns.

# --- seeding content I own -------------------------------------------------

Given("I have posted {string}") do |body|
  Post.create!(body: body, author_sub: persona_sub(@me), author_name: @me)
end

Given("I have posted {string} with a stored image") do |body|
  @stored_key = "#{MediaStorage.prefix_for(persona_sub(@me))}/#{SecureRandom.uuid}.jpg"
  MediaStorage.client.put_object(
    bucket: MediaStorage.bucket, key: @stored_key,
    body: "not-a-real-jpeg", content_type: "image/jpeg"
  )
  Post.create!(body: body, author_sub: persona_sub(@me), author_name: @me,
               media: [{ "key" => @stored_key, "content_type" => "image/jpeg",
                         "width" => 120, "height" => 90 }])
end

Given("I have commented {string} on the post {string}") do |text, post_body|
  post = find_post(post_body)
  Comment.create!(post_id: post.id, body: text, author_sub: persona_sub(@me), author_name: @me)
end

# --- editing / deleting my own content -------------------------------------

When("I edit the post {string} to say {string}") do |old_body, new_body|
  visit edit_post_path(find_post(old_body))
  fill_in "post[body]", with: new_body
  click_button "Save changes"
end

When("I delete the post {string}") do |body|
  @deleted_post_id = find_post(body).id
  visit post_path(@deleted_post_id)
  # The Delete control is a button_to form inside the post card; rack_test
  # submits it regardless of the JS turbo-confirm.
  within(".post") { click_button "Delete" }
end

When("I edit the comment {string} to say {string}") do |old_body, new_body|
  within find(".comment", text: old_body, match: :prefer_exact) do
    # The edit form sits in a closed <details class="comment-edit"> — invisible to
    # Capybara but still submittable under rack_test.
    within(".comment-edit") do
      find("textarea", visible: :all).set(new_body)
      find(:button, "Save", visible: :all).click
    end
  end
end

When("I delete the comment {string}") do |body|
  within find(".comment", text: body, match: :prefer_exact) do
    click_button "Delete"
  end
end

# --- attempts on content I do not own --------------------------------------

When("I try to edit the post {string}") do |body|
  visit edit_post_path(find_post(body)) # authorize! bounces this back to the feed
end

When("I try to delete the comment {string}") do |body|
  # Forge the request the hidden UI never offers. Forgery protection is off in
  # test, so this reaches the controller and is stopped by authorization alone.
  post = Post.recent.first
  comment = find_comment(post, body)
  page.driver.submit :delete, post_comment_path(post, comment), {}
end

# --- assertions ------------------------------------------------------------

Then("I should not see {string}") do |text|
  expect(page).to have_no_content(text)
end

Then("that post's thread is gone") do
  expect(Comment.where(post_id: @deleted_post_id).count).to eq(0)
  expect(Reaction.where(post_id: @deleted_post_id).count).to eq(0)
end

Then("the stored image should be gone") do
  expect do
    MediaStorage.client.head_object(bucket: MediaStorage.bucket, key: @stored_key)
  end.to raise_error(Aws::S3::Errors::NotFound)
end

Then("I should not see any edit or delete control") do
  expect(page).to have_no_css(".owner-actions") # post edit/delete
  expect(page).to have_no_css(".comment__action") # comment delete
  expect(page).to have_no_css(".comment-edit") # comment edit form
end

Then("I am told I can only change my own content") do
  expect(page).to have_content("You can only edit or delete your own posts and comments")
end

Then("the comment {string} is still there") do |body|
  post = Post.recent.first
  expect(Comment.thread_for(post.id).map(&:body)).to include(body)
end
