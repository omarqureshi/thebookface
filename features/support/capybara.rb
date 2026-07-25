# Capybara drives with rack_test (in-process, no browser). That's enough for the
# whole suite: comments and replies are plain form posts, and the image-upload
# scenarios exercise the server contract (presign endpoint + rendering) rather
# than the browser-only canvas/S3 JavaScript.

require "capybara/cucumber"

Capybara.default_driver = :rack_test
Capybara.server = :puma, { Silent: true }
