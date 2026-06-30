# Mixed into the models whose creation can advance a user's funnel stage (see
# User::Funnel). Creating one pushes the owning user to the front of the
# Airtable sync queue so the new stage reaches Airtable -> Loops within ~a
# minute instead of waiting for UserSyncJob's slow round-robin — which is what
# keeps re-engagement emails from firing on a stale stage.
module FunnelResyncTrigger
  extend ActiveSupport::Concern

  included do
    after_create_commit { user&.flag_for_resync! if funnel_milestone? }
  end

  # Whether this record advances the funnel. True by default (the model only
  # exists at the funnel step it represents); models where only some records
  # count — e.g. Post — override it.
  def funnel_milestone? = true
end
