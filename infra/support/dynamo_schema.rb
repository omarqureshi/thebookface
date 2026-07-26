# frozen_string_literal: true

require_relative "app_models"

# Reads a Dynamoid model's table shape — partition/sort keys and GSIs, with the
# DynamoDB attribute types Dynamoid already knows — and turns it into a CDK
# TableV2. The model stays the single source of truth; infra never restates the
# schema, so the two can't drift.
module DynamoSchema
  module_function

  # Build and return the TableV2 for a model: keys, indexes, and removal policy.
  def table(scope, id, model, removal_policy:)
    schema = describe(model)
    props = {
      partition_key: cdk_attr(schema[:partition_key]),
      removal_policy: removal_policy
    }
    props[:sort_key] = cdk_attr(schema[:sort_key]) if schema[:sort_key]
    unless schema[:global_secondary_indexes].empty?
      props[:global_secondary_indexes] = schema[:global_secondary_indexes].map { |g| cdk_gsi(g) }
    end
    AWSCDK::DynamoDB::TableV2.new(scope, id, props)
  end

  # A model's schema as plain data — handy on its own (e.g. for tests):
  # { partition_key:, sort_key:, global_secondary_indexes: [...] }.
  def describe(model)
    {
      partition_key: key_attr(model, model.hash_key),
      sort_key: model.range_key && key_attr(model, model.range_key),
      global_secondary_indexes: model.global_secondary_indexes.values.map { |i| gsi(model, i) }
    }
  end

  # --- reading the model (Dynamoid metadata) ---

  def key_attr(model, name)
    field = model.attributes.fetch(name.to_sym)
    { name: name.to_s, type: Dynamoid::PrimaryKeyTypeMapping.dynamodb_type(field[:type], field) }
  end

  def gsi(model, index)
    {
      index_name: index.name,
      partition_key: key_attr(model, index.hash_key),
      sort_key: index.range_key && key_attr(model, index.range_key),
      projection_type: index.projection_type
    }
  end

  # --- mapping to CDK ---

  ATTRIBUTE_TYPES = {
    string: AWSCDK::DynamoDB::AttributeType::STRING,
    number: AWSCDK::DynamoDB::AttributeType::NUMBER,
    binary: AWSCDK::DynamoDB::AttributeType::BINARY
  }.freeze

  PROJECTION_TYPES = {
    all: AWSCDK::DynamoDB::ProjectionType::ALL,
    keys_only: AWSCDK::DynamoDB::ProjectionType::KEYS_ONLY
  }.freeze

  def cdk_attr(attr)
    { name: attr[:name], type: ATTRIBUTE_TYPES.fetch(attr[:type]) }
  end

  def cdk_gsi(index)
    props = {
      index_name: index[:index_name],
      partition_key: cdk_attr(index[:partition_key]),
      projection_type: PROJECTION_TYPES.fetch(index[:projection_type])
    }
    props[:sort_key] = cdk_attr(index[:sort_key]) if index[:sort_key]
    props
  end
end
