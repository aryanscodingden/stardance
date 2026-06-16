# frozen_string_literal: true

class DailyRollPolicy < ApplicationPolicy
  # Anyone can roll: signed-in rolls save to the account, logged-out rolls go
  # to a cookie (claimed on sign-in).
  def create?
    true
  end

  def leaderboard?
    true
  end

  # History is per-account, so it's signed-in only.
  def history?
    signed_in_any?
  end
end
