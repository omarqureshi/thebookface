# frozen_string_literal: true

namespace :profiles do
  # Rewrite one user's denormalized author fields (author_name / author_avatar on
  # their posts + comments) to match their current profile. Idempotent, scoped to
  # a single sub — this is what the SQS-triggered Lambda runs per message.
  #   rake profiles:reconcile[dev|ada]
  desc "Reconcile a user's denormalized author fields with their profile"
  task :reconcile, [:sub] => :environment do |_task, args|
    sub = args[:sub]
    abort "usage: rake profiles:reconcile[<sub>]" if sub.blank?

    count = ProfileReconciliation.run(sub)
    puts "reconciled #{count} item(s) for #{sub}."
  end
end
