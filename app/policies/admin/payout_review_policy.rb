class Admin::PayoutReviewPolicy < ApplicationPolicy
  def index? = user&.admin?

  def show? = user&.admin?
end
