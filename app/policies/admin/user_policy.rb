class Admin::UserPolicy < ApplicationPolicy
  def index?
    user.admin? || user.fraud_dept? || user.helper?
  end

  def show?
    index?
  end

  def update?
    user.admin? || user.fraud_dept?
  end

  def ban?
    user.admin? || user.fraud_dept?
  end

  def manage_roles?
    user.admin? || user.super_admin?
  end
end
