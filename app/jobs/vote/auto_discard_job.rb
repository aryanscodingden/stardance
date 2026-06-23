class Vote::AutoDiscardJob < ApplicationJob
  queue_as :default

  def perform(vote_id)
    return unless defined?(Secrets::VoteAutoDiscarder)

    vote = Vote.includes(:project, :assignment, :events).find_by(id: vote_id)
    return if vote.nil? || vote.discarded?

    Secrets::VoteAutoDiscarder.call(vote: vote)
  end
end
