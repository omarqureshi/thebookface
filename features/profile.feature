Feature: Editing your profile
  As a signed-in user
  I want a display name and a short bio
  So that people see me the way I want to be seen

  Background:
    Given I am signed in as "Ada Lovelace"

  Scenario: A fresh profile falls back to my Google name
    When I open my profile
    Then I should see "Ada Lovelace"

  Scenario: Setting a display name and bio
    When I set my display name to "Ada, Countess of Lovelace" and bio "First programmer."
    Then I should see "Ada, Countess of Lovelace"
    And I should see "First programmer."

  Scenario: My display name shows across the app
    When I set my display name to "Ada L." and bio ""
    And I open the feed
    Then I should see "Ada L."

  Scenario: Setting a profile photo
    When I set my avatar to an image I uploaded
    Then my profile shows my photo

  Scenario: An avatar key I do not own is ignored
    When I try to set my avatar to someone else's key
    Then my profile has no photo

  Scenario: Renaming reconciles the author name on my existing posts
    When I write a post "Reconcile me"
    And I submit the post
    And I set my display name to "Ada L." and bio ""
    And I open the feed
    # The post's author snapshot was "Ada Lovelace" at write time; the reconcile
    # (run on the profile save) has rewritten it, so the old name is gone.
    Then I should see "Ada L."
    And I should not see "Ada Lovelace"
