# Cucumber environment. This app has no Active Record (it's DynamoDB via
# Dynamoid), so the generated DatabaseCleaner wiring is replaced by our own
# table setup in support/dynamoid.rb.

require "cucumber/rails"

# Let exceptions in the app bubble up to fail the scenario (tag @allow-rescue to
# opt out per scenario).
ActionController::Base.allow_rescue = false
