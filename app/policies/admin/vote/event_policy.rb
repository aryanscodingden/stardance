class Admin::Vote::EventPolicy < ApplicationPolicy
  def index? = user&.can_review? && Post::ShipEvent.payout_feature_enabled?(user)

  def update? = user&.can_review? && Post::ShipEvent.payout_feature_enabled?(user)
end
