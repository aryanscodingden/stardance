# frozen_string_literal: true

# The logged-out visitor's daily roll, kept in a signed cookie instead of the
# database — so it never touches the leaderboard — and claimed onto their
# account when they sign in. Wraps the cookie jar so the cookie name and its
# "value|date" encoding live in exactly one place.
class AnonymousRoll
  COOKIE = :rng_roll

  def initialize(cookies)
    @cookies = cookies
  end

  # Today's roll as an unsaved DailyRoll (so #tone / #flavor work), or nil.
  def today
    value, date = @cookies.signed[COOKIE].to_s.split("|", 2)
    return unless date == Date.current.iso8601 && value.present?

    DailyRoll.new(value: value.to_i, rolled_on: Date.current)
  end

  # Record a fresh roll for today in the cookie and return it (unsaved).
  def store(value)
    @cookies.signed[COOKIE] = {
      value: "#{value}|#{Date.current.iso8601}",
      expires: 2.days.from_now,
      httponly: true,
      same_site: :lax
    }
    DailyRoll.new(value: value, rolled_on: Date.current)
  end

  # Persist today's pending roll onto the user (once), then drop the cookie.
  # No-op when nothing is pending or they've already rolled today.
  def claim!(user)
    pending = today
    @cookies.delete(COOKIE)
    return if pending.nil? || DailyRoll.exists?(user: user, rolled_on: Date.current)

    DailyRoll.create!(user: user, value: pending.value, rolled_on: Date.current)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end
end
