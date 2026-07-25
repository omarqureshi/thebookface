# frozen_string_literal: true

# --- helpers ---------------------------------------------------------------

def find_post(body)
  Post.recent.find { |p| p.body == body } or raise "no post saying #{body.inspect}"
end

def find_comment(post, body)
  Comment.thread_for(post.id).find { |c| c.body == body } or raise "no comment #{body.inspect}"
end

def persona_sub(name)
  key = ApplicationHelper::DEV_PERSONAS.key(name) or raise "unknown persona #{name.inspect}"
  "dev|#{key}"
end

# --- auth (stubbed sign-in via the dev personas) ---------------------------

Given("I am signed in as {string}") do |name|
  visit root_path
  first(:button, name).click # the dev persona button (POST /auth/dev)
end

# --- seed data -------------------------------------------------------------

Given("a post by {string} saying {string}") do |author, body|
  Post.create!(body: body, author_sub: "seed|#{author}", author_name: author)
end

Given("the post {string} has a comment {string} by {string}") do |post_body, text, author|
  post = find_post(post_body)
  Comment.create!(post_id: post.id, body: text, author_sub: "seed|#{author}", author_name: author)
end

Given("the comment {string} has a reply {string} by {string}") do |parent_body, text, author|
  post = Post.recent.first
  parent = find_comment(post, parent_body)
  Comment.create!(post_id: post.id, parent_path: parent.path, body: text,
                  author_sub: "seed|#{author}", author_name: author)
end

# --- navigation & actions --------------------------------------------------

When("I open the post {string}") do |body|
  visit post_path(find_post(body))
end

When("I comment {string}") do |text|
  fill_in "Comment on this post…", with: text
  click_button "Comment"
end

When("I reply {string} to the comment {string}") do |text, comment_body|
  # The reply form lives inside a closed <details>, which Capybara treats as
  # non-visible — so find it explicitly (rack_test submits it regardless).
  within find(".comment", text: comment_body, match: :prefer_exact) do
    find("textarea", visible: :all).set(text)
    find(:button, "Reply", visible: :all).click
  end
end

When("I write a post {string}") do |body|
  visit root_path
  fill_in "post[body]", with: body
end

When("I attach an image to my post") do
  key = "#{MediaStorage.prefix_for(persona_sub('Ada Lovelace'))}/test.jpg"
  media = [{ key: key, content_type: "image/jpeg", width: 120, height: 90 }]
  find("input[name='post[media_json]']", visible: :all).set(media.to_json)
end

When("I submit the post") do
  click_button "Post"
end

When("I attach the fixture image") do
  path = Rails.root.join("features/support/fixtures/sample.jpg").to_s
  attach_file("images", path, make_visible: true) # fires the uploader's change handler
  # The uploader downscales, presigns, and uploads to S3 — the tile gets a
  # data-key once that's done.
  expect(page).to have_css(".upload-tile[data-key]", wait: 20)
end

When("I request an upload for {string}") do |content_type|
  visit root_path
  headers = { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json" }
  token = first('meta[name="csrf-token"]', visible: :all, minimum: 0)&.[]("content")
  headers["HTTP_X_CSRF_TOKEN"] = token if token
  page.driver.post uploads_path, { content_type: content_type }.to_json, headers
  @upload = JSON.parse(page.driver.response.body)
end

# --- assertions ------------------------------------------------------------

Then("I should see {string}") do |text|
  expect(page).to have_content(text)
end

Then("the comment {string} should be nested at depth {int}") do |body, depth|
  el = find(".comment", text: body, match: :prefer_exact)
  expect(el["style"]).to include("--indent: #{depth}")
end

Then("I should see the attached image") do
  expect(page).to have_css(".media__item img")
end

Then("the attached image loads") do
  expect(page).to have_css(".media__item img")
  # naturalWidth turns positive once the browser has fetched it back from S3.
  loaded = false
  Timeout.timeout(15) do
    until loaded
      loaded = page.evaluate_script(
        "(() => { const i = document.querySelector('.media__item img'); return !!(i && i.complete && i.naturalWidth > 0); })()"
      )
      sleep 0.25 unless loaded
    end
  end
  expect(loaded).to be(true)
end

Then("I receive a presigned upload target") do
  expect(@upload).to include("url", "key")
  expect(@upload["fields"]).to include("policy", "x-amz-signature")
  expect(@upload["key"]).to start_with("uploads/")
end
