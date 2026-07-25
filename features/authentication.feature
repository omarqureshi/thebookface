Feature: Signing in
  As a visitor
  I want to sign in
  So that I can post, comment, and react

  Scenario: Stubbed Google sign-in
    Given I am signed in as "Ada Lovelace"
    Then I should see "Signed in as Ada Lovelace"
    And I should see "Log out"
