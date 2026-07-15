class MissionSubmissionsController < ApplicationController
  before_action :set_body_class
  before_action :set_submission

  def redeem
    authorize @submission
    prizes = @submission.mission.prizes.ordered.includes(:shop_item).to_a

    if prizes.size == 1
      redirect_to shop_item_path(prizes.first.shop_item, mission_submission_id: @submission.id)
    else
      @prizes = prizes
    end
  end

  private

  def set_body_class
    @body_class = "app-layout-page"
  end

  def set_submission
    @submission = Mission::Submission.find(params[:id])
  end
end
