# DynamoDB test setup. The suite runs against DynamoDB Local (docker compose up),
# which the Dynamoid initializer already targets in the test environment. We
# create the tables once, then purge every item before each scenario for a clean
# slate — cheaper than dropping/recreating tables each time.

MODELS = [Post, Comment, Reaction].freeze

# Create tables up front (idempotent — ignore "already exists").
MODELS.each do |model|
  model.create_table(sync: true)
rescue Dynamoid::Errors::Error, Aws::DynamoDB::Errors::ResourceInUseException
  # already there
end

Before do
  MODELS.each { |model| model.each(&:delete) }
end
