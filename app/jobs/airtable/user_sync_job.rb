class Airtable::UserSyncJob < Airtable::BaseSyncJob
  def table_name = "_users"

  # Only sync users with emails to avoid duplicate nil key issues in Airtable
  def records = User.where.not(email: [ nil, "" ])

  def primary_key_field = "email"

  # Backstop round-robin for the funnel-stuck nudges. Freshness for users who
  # actually advance is handled event-driven by FunnelResyncTrigger (their
  # synced_at is nulled, jumping them to the front); this limit just bounds how
  # long anything those hooks miss can stay stale. 100/min cycles ~29k users in
  # ~5h — well under the 2-day nudge window. Norairrecord's Faraday middleware
  # paces requests to Airtable's 5 req/s per-base limit on its own.
  def sync_limit = 100

  def field_mapping(user)
    address = user.addresses.first

    fields = {
      "first_name" => user.first_name,
      "last_name" => user.last_name,
      "email" => user.email,
      "slack_id" => user.slack_id,
      "avatar_url" => "https://cachet.hackclub.com/users/#{user.slack_id}/r",
      "has_commented" => user.comments.exists?,
      "has_some_role_of_access" => user.roles.any?,
      "hours" => user.all_time_coding_seconds&.fdiv(3600),
      "verification_status" => user.verification_status.to_s,
      "funnel_stage" => user.funnel_stage.to_s,
      "funnel_stage_entered_at" => user.funnel_stage_entered_at,
      "created_at" => user.created_at,
      "synced_at" => Time.now,
      "is_banned" => user.banned,
      "star_id" => user.id.to_s,
      "ref" => user.ref
    }

    if address.present?
      fields.merge!(
        "address_line_1" => address["line_1"],
        "address_line_2" => address["line_2"],
        "address_city" => address["city"],
        "address_state" => address["state"],
        "address_postal_code" => address["postal_code"],
        "address_country" => address["country"]
      )
    end

    fields
  end
end
