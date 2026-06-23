class OneTime::BackfillVoteAutoDiscardsJob < ApplicationJob
  queue_as :literally_whenever

  def scope
    Vote
      .where(discarded: false)
      .where.not(id: Vote::Event.accepted_vote_flags.select(:vote_id))
  end

  def perform(batch_size: 1_000)
    return unless defined?(Secrets::VoteAutoDiscarder)

    count = 0

    scope.find_each(batch_size: batch_size) do |vote|
      Vote::AutoDiscardJob.perform_later(vote.id)
      count += 1
    end

    Rails.logger.info "[OneTime::BackfillVoteAutoDiscards] Enqueued #{count} vote auto-discard jobs"
  end
end
