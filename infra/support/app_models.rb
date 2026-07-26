# frozen_string_literal: true

# Loads the Rails app's Dynamoid models into the CDK process, so the stack can
# build each DynamoDB table straight from its model definition — one source of
# truth for keys and indexes, with nothing about the schema restated in infra.
#
# The models are loaded schema-only: all we need are dynamoid and the class
# bodies, not a running Rails app or a DynamoDB connection. Their one load-time
# tie to Rails is the runtime table-name lookup — a value the CDK never uses,
# because it assigns the physical table name itself — so a tiny stand-in answers
# exactly that lookup and nothing more. If a model ever grows a new load-time
# dependency, synth fails loudly here and this loader gets extended.

require "dynamoid"
require "active_support/ordered_options"

unless defined?(Rails)
  module Rails
    # Answers Rails.application.config.x.dynamodb.<name>_table with placeholders.
    def self.application
      @application ||= begin
        dynamodb = ActiveSupport::OrderedOptions.new
        dynamodb.posts_table = "posts"
        dynamodb.comments_table = "comments"
        dynamodb.reactions_table = "reactions"
        dynamodb.profiles_table = "profiles"
        x = ActiveSupport::OrderedOptions.new
        x.dynamodb = dynamodb
        config = ActiveSupport::OrderedOptions.new
        config.x = x
        Struct.new(:config).new(config)
      end
    end
  end
end

models_dir = File.expand_path("../../app/models", __dir__)
%w[post comment reaction profile].each { |m| require File.join(models_dir, m) }

module AppModels
  # Construct id => Dynamoid model, in the order the stack creates them.
  TABLES = { "Posts" => Post, "Comments" => Comment, "Reactions" => Reaction,
             "Profiles" => Profile }.freeze
end
