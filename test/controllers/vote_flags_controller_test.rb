require "test_helper"

class VoteFlagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Flipper.enable(:ship_event_payouts)
  end

  teardown do
    Flipper.disable(:ship_event_payouts)
  end

  test "owner can view and flag vote reasons during payout review" do
    owner, vote = create_reviewable_vote
    sign_in owner

    get ship_event_vote_reasons_path(vote.ship_event)
    assert_response :success
    assert_includes response.body, "Strong implementation details"

    assert_difference -> { Vote::Event.pending_vote_flags.count }, 1 do
      post vote_flag_path(vote)
    end
    assert_redirected_to ship_event_vote_reasons_path(vote.ship_event)
  end

  test "owner reason review is hidden while payout flag is off" do
    owner, vote = create_reviewable_vote
    Flipper.disable(:ship_event_payouts)
    sign_in owner

    get ship_event_vote_reasons_path(vote.ship_event)
    assert_response :not_found
  end

  test "admin can review vote flags" do
    owner, vote = create_reviewable_vote
    vote.flag_for_review_by(owner)
    admin = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "admin#{SecureRandom.hex(4)}")
    admin.grant_role!(:admin)
    sign_in admin

    get admin_vote_flags_path
    assert_response :success
    assert_includes response.body, "Strong implementation details"

    assert_difference -> { Vote.payout_countable.count }, -1 do
      post admin_vote_flag_approval_path(vote.pending_flag)
    end
    assert_redirected_to admin_vote_flags_path
  end

  private
    def create_reviewable_vote
      owner = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "owner#{SecureRandom.hex(4)}")
      project = Project.create!(title: "Project #{SecureRandom.hex(4)}")
      Project::Membership.create!(project: project, user: owner, role: :owner)
      ship_event = Post::ShipEvent.create!(body: "Ship it", uploading_attachments: true, certification_status: "approved", hours_at_ship: 2)
      Post.create!(project: project, user: owner, postable: ship_event)
      ship_event.update!(hours_at_ship: 2)

      votes = Array.new(Post::ShipEvent::VOTES_REQUIRED_FOR_PAYOUT) do |index|
        voter = create_user(slack_id: "U#{SecureRandom.hex(8)}", display_name: "voter#{SecureRandom.hex(4)}#{index}")
        Vote.create!(
          user: voter,
          project: project,
          ship_event: ship_event,
          reason: "Strong implementation details with clear progress and thoughtful trade offs.",
          originality_score: 6,
          technical_score: 6,
          usability_score: 6,
          storytelling_score: 6
        )
      end

      ship_event.refresh_payout_score!
      ship_event.issue_payout!

      [ owner, votes.first ]
    end
end
