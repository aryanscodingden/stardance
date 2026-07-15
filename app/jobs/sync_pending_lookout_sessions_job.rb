# frozen_string_literal: true

# Re-polls recent non-terminal Lookout sessions so their recordings finalize
# even when nobody has the recorder/project page open.
#
# A LookoutSession only advances to `complete` (and gains a playable
# recording_url) when we poll Lookout's client API after Lookout has finished
# compiling the video. The in-browser recorder polls while its tab is open, but
# a builder who closes the tab before compile finishes leaves the session stuck
# `pending` forever: the tracked time still reaches Hackatime, but the recording
# never appears on the hardware review page, and reviewers can't trigger the
# sync themselves (the review page only reads already-finalized rows). This job
# is the missing server-side poller.
#
# Bounded on purpose: Lookout's recordings and presigned URLs expire, so a
# session that has not finalized within SYNC_WINDOW never will. We only re-poll
# sessions started inside that window, newest first (most likely to still be
# retrievable), capped per run, and skip ones a live recorder just created.
# Anything older or over the cap is left to OneTime::BackfillLookoutSessionsJob.
class SyncPendingLookoutSessionsJob < ApplicationJob
  queue_as :default

  # How far back a session can be and still plausibly finalize.
  SYNC_WINDOW = 1.day
  # Upper bound on Lookout calls per run, so a backlog can't blow up one run.
  MAX_PER_RUN = 400
  # Give the in-browser recorder's own poll a moment before we double-poll a
  # freshly created session.
  MIN_AGE = 30.seconds

  def perform
    sessions = LookoutSession.syncable
                             .where(started_at: SYNC_WINDOW.ago..MIN_AGE.ago)
                             .order(started_at: :desc)
                             .limit(MAX_PER_RUN)
                             .to_a
    return if sessions.empty?

    synced = 0
    newly_complete = 0
    errored = 0

    sessions.each do |session|
      remote = LookoutService.fetch_session(session.token)
      next unless remote

      before = session.status
      session.sync_from_remote!(remote)
      synced += 1
      newly_complete += 1 if before != "complete" && session.status == "complete"
    rescue => e
      errored += 1
      Rails.logger.error "[SyncPendingLookoutSessions] session=#{session.id} token=#{session.token} error=#{e.message}"
    end

    Rails.logger.info(
      "[SyncPendingLookoutSessions] polled=#{sessions.size} synced=#{synced} " \
      "newly_complete=#{newly_complete} errored=#{errored}"
    )
  end
end
