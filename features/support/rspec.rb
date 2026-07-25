# Use RSpec expectations (and Capybara's matchers, which build on them) in steps.
require "rspec/expectations"

World(RSpec::Matchers)
World(Capybara::RSpecMatchers)
