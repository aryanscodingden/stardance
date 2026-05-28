class Admin::Fraud::DashboardPolicy < ApplicationPolicy
  def show?
    user.admin? || user.fraud_dept?
  end
end
