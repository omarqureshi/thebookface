Feature: Reacting to posts and comments
  As a signed-in user
  I want to react with an emoji and change my mind
  So that I can respond without writing a comment

  Background:
    Given I am signed in as "Ada Lovelace"
    And a post by "Grace Hopper" saying "React to me"

  Scenario: Reacting to a post
    When I open the post "React to me"
    And I react "👍" to the post
    Then I should see "👍 1"

  Scenario: Switching my reaction replaces the old one
    When I open the post "React to me"
    And I react "👍" to the post
    And I react "❤️" to the post
    Then I should see "❤️ 1"
    And I should not see "👍 1"

  Scenario: Reacting again with the same emoji takes it back
    When I open the post "React to me"
    And I react "👍" to the post
    And I react "👍" to the post
    Then the post has no reaction counts

  Scenario: Reacting to a comment
    Given the post "React to me" has a comment "First!" by "Alan Turing"
    When I open the post "React to me"
    And I react "😂" to the comment "First!"
    Then I should see "😂 1"
