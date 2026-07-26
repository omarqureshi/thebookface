Feature: Editing and deleting your own content
  As a signed-in user
  I want to edit and delete the posts and comments I authored — and only those
  So that I can fix mistakes and clean up after myself without touching others'

  Background:
    Given I am signed in as "Ada Lovelace"

  Scenario: Editing my own post
    Given I have posted "Frist post"
    When I edit the post "Frist post" to say "First post"
    Then I should see "First post"
    And I should not see "Frist post"

  Scenario: Deleting my own post takes its whole thread with it
    Given I have posted "Regrettable take"
    And the post "Regrettable take" has a comment "Couldn't agree more" by "Grace Hopper"
    When I delete the post "Regrettable take"
    Then I should not see "Regrettable take"
    And that post's thread is gone

  Scenario: Deleting my own post reaps its images from the store
    Given I have posted "Holiday snap" with a stored image
    When I delete the post "Holiday snap"
    Then the stored image should be gone

  Scenario: Editing my own comment
    Given a post by "Grace Hopper" saying "Open thread"
    And I have commented "Helo" on the post "Open thread"
    When I open the post "Open thread"
    And I edit the comment "Helo" to say "Hello there"
    Then I should see "Hello there"

  Scenario: Deleting my own comment that has no replies removes it outright
    Given a post by "Grace Hopper" saying "Open thread"
    And I have commented "Never mind" on the post "Open thread"
    When I open the post "Open thread"
    And I delete the comment "Never mind"
    Then I should not see "Never mind"

  Scenario: Deleting my own comment that has replies leaves a tombstone
    Given a post by "Grace Hopper" saying "Open thread"
    And I have commented "Original point" on the post "Open thread"
    And the comment "Original point" has a reply "Building on that" by "Alan Turing"
    When I open the post "Open thread"
    And I delete the comment "Original point"
    Then I should see "[comment deleted]"
    And I should see "Building on that"
    And I should not see "Original point"

  Scenario: I get no edit or delete controls on someone else's content
    Given a post by "Grace Hopper" saying "Not yours"
    And the post "Not yours" has a comment "Hands to yourself" by "Alan Turing"
    When I open the post "Not yours"
    Then I should not see any edit or delete control

  Scenario: I cannot reach the edit page of a post I do not own
    Given a post by "Grace Hopper" saying "Off limits"
    When I try to edit the post "Off limits"
    Then I am told I can only change my own content

  Scenario: A forged delete of someone else's comment is refused
    Given a post by "Grace Hopper" saying "Guarded thread"
    And the post "Guarded thread" has a comment "Untouchable" by "Alan Turing"
    When I try to delete the comment "Untouchable"
    Then the comment "Untouchable" is still there
