class Admin::Certification::IntegrityController < Admin::Certification::ApplicationController
  def index
    authorize :integrity, policy_class: Admin::Certification::IntegrityPolicy

    @reviews = ::Certification::Integrity
      .pending
      .includes(ship_event: [ :project, { post: :user } ])
      .order(created_at: :asc)
  end

  def show
    @review = ::Certification::Integrity.find(params[:id])
    authorize @review, policy_class: Admin::Certification::IntegrityPolicy
  end
end
