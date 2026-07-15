require "test_helper"

class OneTime::BackfillLookoutSessionsJobTest < ActiveJob::TestCase
  setup do
    @user = create_user(slack_id: "U_BF", display_name: "bf")
    @project = Project.create!(title: "Robot arm", hardware_stage: "build")
    @project.memberships.create!(user: @user, role: :owner)
  end

  test "dry run reports the count and writes nothing" do
    @project.lookout_sessions.create!(user: @user, token: "p1", status: "pending", started_at: 10.days.ago)
    @project.lookout_sessions.create!(user: @user, token: "c1", status: "complete", started_at: 1.day.ago)

    polled = false
    LookoutService.stub(:fetch_session, ->(*) { polled = true; {} }) do
      result = OneTime::BackfillLookoutSessionsJob.perform_now # dry_run: true by default

      assert_equal 1, result
    end

    assert_not polled, "dry run must not poll Lookout"
    assert_equal "pending", LookoutSession.find_by(token: "p1").status
  end

  test "real run recovers whatever Lookout still has" do
    stuck = @project.lookout_sessions.create!(user: @user, token: "p1", status: "pending", started_at: 10.days.ago)

    remote = { status: "complete", trackedSeconds: 1200, videoUrl: "https://lookout.test/v/p1" }
    LookoutService.stub(:fetch_session, remote) do
      result = OneTime::BackfillLookoutSessionsJob.perform_now(dry_run: false)

      assert_equal 1, result[:recovered]
    end

    stuck.reload
    assert_equal "complete", stuck.status
    assert_equal "https://lookout.test/v/p1", stuck.recording_url
  end

  test "real run leaves a session Lookout never finalized untouched" do
    stuck = @project.lookout_sessions.create!(user: @user, token: "p2", status: "pending", started_at: 8.days.ago)

    # Lookout still reports it pending with no video — nothing to recover.
    LookoutService.stub(:fetch_session, { status: "pending" }) do
      result = OneTime::BackfillLookoutSessionsJob.perform_now(dry_run: false)

      assert_equal 0, result[:recovered]
    end

    stuck.reload
    assert_equal "pending", stuck.status
    assert_nil stuck.recording_url
  end

  test "max_age_days bounds how far back the sweep reaches" do
    @project.lookout_sessions.create!(user: @user, token: "recent", status: "pending", started_at: 2.days.ago)
    @project.lookout_sessions.create!(user: @user, token: "ancient", status: "pending", started_at: 30.days.ago)

    polled = []
    fetch = ->(token) { polled << token; { status: "pending" } }
    LookoutService.stub(:fetch_session, fetch) do
      OneTime::BackfillLookoutSessionsJob.perform_now(dry_run: false, max_age_days: 7)
    end

    assert_includes polled, "recent"
    assert_not_includes polled, "ancient"
  end
end
