class Projects::MissionResubmissionsController < ApplicationController
  before_action :set_project

  def create
    authorize @project, :request_mission_resubmission?

    submission = @project.last_ship_event&.mission_submission

    unless submission&.rejected?
      redirect_to project_path(@project), alert: "No rejected mission submission to resubmit." and return
    end

    Mission::Submission.transaction do
      submission.update!(reviewed_by: nil, reviewed_at: nil, rejection_message: nil,
                         claimed_at: nil, claim_expires_at: nil)
      submission.undo!
    end

    redirect_to project_path(@project), notice: "Re-review requested! Your submission is back in the mission review queue."
  rescue AASM::InvalidTransition
    redirect_to project_path(@project), alert: "This submission can't be re-submitted right now."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
