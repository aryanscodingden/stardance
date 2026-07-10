class Projects::RecertificationsController < ApplicationController
  before_action :set_project

  def create
    authorize @project, :request_recertification?

    @project.with_lock do
      latest_review = @project.ship_reviews.order(created_at: :desc, id: :desc).first

      if latest_review&.pending?
        redirect_to project_path(@project), alert: "A review is already pending for this project." and return
      end

      @project.resubmit_for_review!
      ship_event = @project.last_ship_event
      cert = @project.ship_reviews.create!(status: :pending, post_ship_event_id: ship_event&.id)
      ship_event&.update!(certification_status: "pending")

      ::ExternalDashboard::ShipWebhookJob.perform_later(cert.id)
    end

    redirect_to project_path(@project), notice: "Re-certification requested! Your project is back in the review queue."
  rescue AASM::InvalidTransition
    alert = @project.ship_blocker_message || "Your project can't be re-submitted right now."
    redirect_to project_path(@project), alert: alert
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
