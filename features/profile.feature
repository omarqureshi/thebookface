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
