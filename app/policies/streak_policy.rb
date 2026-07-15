class StreakPolicy < ApplicationPolicy
  def calendar?
    user.present?
  end
end
