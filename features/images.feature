Feature: Attaching images to posts
  As a signed-in user
  I want to attach an image to a post
  So that I can share photos

  Background:
    Given I am signed in as "Ada Lovelace"

  # The browser uploads straight to S3 with this target — covering the server
  # side of the flow (the canvas/S3 JavaScript is browser-only).
  Scenario: The composer can request a presigned upload
    When I request an upload for "image/jpeg"
    Then I receive a presigned upload target

  # After the browser has uploaded, the post form carries the object key(s); the
  # post then renders the image.
  Scenario: A post with an attached image shows the image
    When I write a post "Look at this!"
    And I attach an image to my post
    And I submit the post
    Then I should see "Look at this!"
    And I should see the attached image

  # The real thing in headless Chrome: pick a file, the Stimulus controller
  # downscales it, uploads it straight to S3 (MinIO), and the post shows an image
  # the browser then loads back. Needs the test container (Dockerfile.test).
  @javascript
  Scenario: Uploading an image through the browser, end to end
    When I write a post "A real browser upload"
    And I attach the fixture image
    And I submit the post
    Then I should see "A real browser upload"
    And the attached image loads
