# frozen_string_literal: true

# Authorization rules (CanCanCan). Kept deliberately small: reading is open, and
# a signed-in user may create, and edit/delete their *own* posts and comments —
# ownership is just an author_sub match, which CanCanCan evaluates as a plain
# attribute comparison on the loaded object (no ActiveRecord needed).
class Ability
  include CanCan::Ability

  def initialize(user)
    can :read, [Post, Comment]

    return if user.nil? # signed out → read-only

    can :create, [Post, Comment, Reaction]
    can %i[update destroy], [Post, Comment], author_sub: user.sub
  end
end
