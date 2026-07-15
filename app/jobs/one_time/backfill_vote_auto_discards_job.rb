class OneTime::BackfillVoteAutoDiscardsJob < ApplicationJob
  queue_as :literally_whenever

  def scope
    Vote
      .where(discarded: false)
      .where.not(id: Vote::Event.accepted_vote_flags.select(:vote_id))
  end

  def perform(batch_size: 1_000)
    unless vote_auto_discarder_available?
      Rails.logger.warn "[OneTime::BackfillVoteAutoDiscards] Skipped because Secrets::VoteAutoDiscarder is unavailable"
      return 0
    end

    count = 0

    scope.find_each(batch_size: batch_size) do |vote|
      Vote::AutoDiscardJob.perform_later(vote.id)
      count += 1
    end

    Rails.logger.info "[OneTime::BackfillVoteAutoDiscards] Enqueued #{count} vote auto-discard jobs"
    count
  end

  private
    def vote_auto_discarder_available?
      "Secrets::VoteAutoDiscarder".safe_constantize.present?
    end
end
