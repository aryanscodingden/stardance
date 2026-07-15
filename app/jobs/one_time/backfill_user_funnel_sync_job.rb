module OneTime
  # One-shot full backfill of every user's funnel fields into Airtable. Unlike
  # the steady Airtable::UserSyncJob round-robin (capped at sync_limit/min so it
  # stays gentle), this pages through *all* users and upserts them as fast as
  # Airtable allows. Run once after deploying the funnel sync, or any time the
  # Airtable mirror needs a full rebuild:
  #
  #   OneTime::BackfillUserFunnelSyncJob.perform_later
  #
  # Pacing: Norairrecord's rate limiter is per-process and caps us at Airtable's
  # 5 req/s per base (10 records/request = ~50 users/s), so ~29k users take
  # ~10 min. Keep it a SINGLE job — fanning out across worker processes would
  # each get their own 5 req/s budget and collectively trip Airtable's limit.
  # Idempotent (upsert by email), so it's safe to re-run if a batch fails.
  class BackfillUserFunnelSyncJob < Airtable::UserSyncJob
    BATCH_SIZE = 500

    def perform
      records.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        airtable_records = batch
          .map { |user| table.new(field_mapping(user)) }
          .reject { |record| record.fields[primary_key_field].blank? }
          .uniq { |record| record.fields[primary_key_field] }
        next if airtable_records.empty?

        table.batch_upsert(airtable_records, primary_key_field)
        records.unscoped.where(id: batch.map(&:id)).update_all(synced_at_field => Time.now)
      rescue Norairrecord::Error => e
        Rails.logger.error("[#{self.class.name}] batch failed (#{e.message}); continuing — re-run to retry")
      end
    end
  end
end
