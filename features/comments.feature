Feature: Comments and nested replies
  As a signed-in user
  I want to comment on posts and reply to comments (and to replies)
  So that conversations can thread

  Background:
    Given I am signed in as "Ada Lovelace"
    And a post by "Grace Hopper" saying "Hello Bookface"

  Scenario: Commenting on a post
    When I open the post "Hello Bookface"
    And I comment "Nice first post!"
    Then I should see "Nice first post!"
    And I should see "1 comment"

  Scenario: Replying to a comment
    Given the post "Hello Bookface" has a comment "First!" by "Grace Hopper"
    When I open the post "Hello Bookface"
    And I reply "Right behind you" to the comment "First!"
    Then I should see "Right behind you"
    And the comment "Right behind you" should be nested at depth 1

  Scenario: Replying to a reply
    Given the post "Hello Bookface" has a comment "Top level" by "Grace Hopper"
    And the comment "Top level" has a reply "A reply" by "Alan Turing"
    When I open the post "Hello Bookface"
    And I reply "A reply to the reply" to the comment "A reply"
    Then I should see "A reply to the reply"
    And the comment "A reply to the reply" should be nested at depth 2

  Scenario: An empty comment is rejected and the page still renders
    Given the post "Hello Bookface" has a comment "First!" by "Grace Hopper"
    When I open the post "Hello Bookface"
    And I comment ""
    Then I should see "Hello Bookface"
    And I should see "1 comment"
