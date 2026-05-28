class Admin::Shop::SuggestionPolicy < ApplicationPolicy
  def index?
    user.admin?
  end

  def destroy?
    user.admin?
  end

  def update?
    user.admin?
  end
end
