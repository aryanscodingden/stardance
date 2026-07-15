class Vote::AutoDiscardJob < ApplicationJob
  queue_as :default

  def perform(vote_id)
    vote_auto_discarder = "Secrets::VoteAutoDiscarder".safe_constantize
    return unless vote_auto_discarder

    vote = Vote.includes(:project, :assignment, :events).find_by(id: vote_id)
    return if vote.nil? || vote.discarded?

    vote_auto_discarder.call(vote: vote)
  end
end
