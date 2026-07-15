require "test_helper"

class Vote::AutoDiscardJobTest < ActiveJob::TestCase
  include VotingFactory

  teardown do
    Secrets.send(:remove_const, :VoteAutoDiscarder) if defined?(Secrets::VoteAutoDiscarder)
  end

  test "delegates vote evaluation to the secrets auto discarder" do
    vote = create_vote
    calls = []

    discarder = Class.new do
      define_singleton_method(:call) do |vote:|
        calls << vote
        vote.auto_discard!(properties: { detector: "test" })
      end
    end
    Secrets.const_set(:VoteAutoDiscarder, discarder)

    assert_difference -> { Vote::Event.of_type("vote_auto_discarded").count }, 1 do
      Vote::AutoDiscardJob.perform_now(vote.id)
    end

    assert_equal [ vote ], calls
    assert vote.reload.discarded?
    assert_not_includes Vote.payout_countable, vote
    assert_equal "test", Vote::Event.of_type("vote_auto_discarded").last.properties["detector"]
  end

  test "does nothing when secrets auto discarder is unavailable" do
    vote = create_vote

    assert_no_difference -> { Vote::Event.of_type("vote_auto_discarded").count } do
      assert_nothing_raised { Vote::AutoDiscardJob.perform_now(vote.id) }
    end

    assert_not vote.reload.discarded?
    assert_includes Vote.payout_countable, vote
  end

  test "does not call secrets for already discarded votes" do
    vote = create_vote
    vote.update!(discarded: true)
    called = false

    discarder = Class.new do
      define_singleton_method(:call) do |vote:|
        called = true
      end
    end
    Secrets.const_set(:VoteAutoDiscarder, discarder)

    Vote::AutoDiscardJob.perform_now(vote.id)

    assert_not called
  end

  private
    def create_vote
      voter = create_eligible_voter
      ship_event = create_voteable_ship_event
      assignment = Vote::Assignment.create!(user: voter, ship_event: ship_event)

      assignment.submit_vote(
        originality_score: 6,
        technical_score: 6,
        usability_score: 6,
        storytelling_score: 6,
        reason: "Strong implementation details with clear progress and thoughtful trade offs."
      )
    end
end
