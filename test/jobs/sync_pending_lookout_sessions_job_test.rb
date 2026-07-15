require "test_helper"

class SyncPendingLookoutSessionsJobTest < ActiveJob::TestCase
  setup do
    @user = create_user(slack_id: "U_SYNC", display_name: "sync")
    @project = Project.create!(title: "Robot arm", hardware_stage: "build")
    @project.memberships.create!(user: @user, role: :owner)
  end

  def session(token:, status:, started_at:)
    @project.lookout_sessions.create!(user: @user, token: token, status: status, started_at: started_at)
  end

  test "finalizes a recent non-terminal session from Lookout" do
    fresh = session(token: "fresh", status: "pending", started_at: 2.hours.ago)

    remote = { status: "complete", trackedSeconds: 900, videoUrl: "https://lookout.test/v/fresh" }
    LookoutService.stub(:fetch_session, remote) do
      SyncPendingLookoutSessionsJob.perform_now
    end

    fresh.reload
    assert_equal "complete", fresh.status
    assert_equal 900, fresh.duration_seconds
    assert_equal "https://lookout.test/v/fresh", fresh.recording_url
  end

  test "skips sessions older than the sync window" do
    old = session(token: "old", status: "pending", started_at: 5.days.ago)

    polled = []
    fetch = ->(token) { polled << token; { status: "complete", videoUrl: "https://lookout.test/v/#{token}" } }
    LookoutService.stub(:fetch_session, fetch) do
      SyncPendingLookoutSessionsJob.perform_now
    end

    assert_not_includes polled, "old"
    assert_equal "pending", old.reload.status
  end

  test "skips terminal sessions" do
    done = session(token: "done", status: "complete", started_at: 1.hour.ago)

    polled = []
    fetch = ->(token) { polled << token; {} }
    LookoutService.stub(:fetch_session, fetch) do
      SyncPendingLookoutSessionsJob.perform_now
    end

    assert_not_includes polled, "done"
  end

  test "skips brand-new sessions the live recorder is still polling" do
    just_now = session(token: "justnow", status: "pending", started_at: 5.seconds.ago)

    polled = []
    fetch = ->(token) { polled << token; { status: "complete", videoUrl: "x" } }
    LookoutService.stub(:fetch_session, fetch) do
      SyncPendingLookoutSessionsJob.perform_now
    end

    assert_not_includes polled, "justnow"
    assert_equal "pending", just_now.reload.status
  end

  test "one bad session does not abort the run" do
    boom = session(token: "boom", status: "pending", started_at: 3.hours.ago)
    ok = session(token: "ok", status: "pending", started_at: 2.hours.ago)

    fetch = lambda do |token|
      raise "lookout exploded" if token == "boom"

      { status: "complete", trackedSeconds: 10, videoUrl: "https://lookout.test/v/#{token}" }
    end

    LookoutService.stub(:fetch_session, fetch) do
      assert_nothing_raised { SyncPendingLookoutSessionsJob.perform_now }
    end

    assert_equal "pending", boom.reload.status
    assert_equal "complete", ok.reload.status
  end
end
