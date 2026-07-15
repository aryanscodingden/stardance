# frozen_string_literal: true

# Authorizes the combined hardware review page. The record is the Project being
# reviewed. Same bar as the funding/ship review pages: the user must be a
# reviewer and must not own the project they're reviewing.
class Admin::Certification::HardwareReviewPolicy < ApplicationPolicy
  def index?
    user&.can_review?
  end

  def next?
    index?
  end

  def show?
    user&.can_review? && not_own_project?
  end

  private

  def not_own_project?
    !user.memberships.exists?(project_id: record.id)
  end
end
