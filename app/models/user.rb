# frozen_string_literal: true

# A signed-in user. Deliberately NOT persisted: Cognito is the system of record
# for users (they sign in with Google, federated through the Cognito user pool).
# We only carry the claims we need — the stable subject id, email, and display
# name — in the session, and reconstruct this value object from them.
class User
  attr_reader :sub, :email, :name

  def initialize(attrs)
    attrs = attrs.stringify_keys
    @sub = attrs["sub"]
    @email = attrs["email"]
    @name = attrs["name"].presence || attrs["email"]
  end

  def initials
    name.to_s.split(/\s+/).map { |part| part[0] }.first(2).join.upcase.presence || "?"
  end

  def to_session
    { "sub" => sub, "email" => email, "name" => name }
  end
end
