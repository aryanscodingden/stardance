class Post::ShipEventPolicy < ApplicationPolicy
  def vote_reasons?
    Post::ShipEvent.payout_feature_enabled?(user) &&
      record.payout_basis_locked_at.present? &&
      record.payout.blank? &&
      record.project&.memberships&.where(role: :owner, user: user)&.exists?
  end
end
