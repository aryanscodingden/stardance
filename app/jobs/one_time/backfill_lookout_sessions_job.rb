# frozen_string_literal: true

# One-off recovery sweep for Lookout sessions that got stuck `pending` because
# nothing ever polled them through to completion. SyncPendingLookoutSessionsJob
# is the ongoing fix and carries the full root-cause writeup; this job reclaims
# the pre-existing backlog that built up before that poller existed.
#
# Re-polls every non-terminal session against Lookout's client API and mirrors
# back whatever Lookout still holds: a session Lookout finalized flips to
# `complete` and gains a playable recording_url; a session Lookout never
# finalized (tab closed before anything recorded) or has since expired stays as
# it is. We cannot recover a video Lookout no longer has — this only reclaims
# what is still retrievable, so expect older sessions to stay stuck.
#
# DRY RUN BY DEFAULT: logs how many sessions it would poll and writes nothing.
# Pass dry_run: false to actually poll Lookout and persist. `max_age_days:`
# bounds how far back to reach (nil = all time); start narrow to gauge the hit
# rate before sweeping the whole backlog.
class OneTime::BackfillLookoutSessionsJob < ApplicationJob
  queue_as :literally_whenever

  # Non-terminal sessions to attempt, optionally limited to a recent window.
  def scope(max_age_days)
    rel = LookoutSession.syncable
    rel = rel.where(started_at: max_age_days.days.ago..) if max_age_days
    rel
  end

  def perform(dry_run: true, max_age_days: nil)
    sessions = scope(max_age_days)

    if dry_run
      window = max_age_days ? " (last #{max_age_days}d)" : ""
      Rails.logger.info "[BackfillLookoutSessions] DRY RUN — would poll #{sessions.count} non-terminal session(s)#{window}"
      return sessions.count
    end

    polled = 0
    recovered = 0
    errored = 0

    sessions.find_each(batch_size: 200) do |session|
      remote = LookoutService.fetch_session(session.token)
      next unless remote

      before = session.status
      session.sync_from_remote!(remote)
      polled += 1
      recovered += 1 if before != "complete" && session.status == "complete"
    rescue => e
      errored += 1
      Rails.logger.error "[BackfillLookoutSessions] session=#{session.id} token=#{session.token} error=#{e.message}"
    end

    Rails.logger.info "[BackfillLookoutSessions] polled=#{polled} recovered=#{recovered} errored=#{errored}"
    { polled: polled, recovered: recovered, errored: errored }
  end
end
