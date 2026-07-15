class Votes::FlagsController < ApplicationController
  before_action -> { head :not_found unless Post::ShipEvent.payout_feature_enabled?(current_user) }

  def create
    @vote = Vote.find(params[:vote_id])
    authorize @vote, :flag?

    if @vote.flag_for_review_by(current_user)
      redirect_to project_path(@vote.project, anchor: "payout-review"), notice: "Rating flagged for review."
    else
      redirect_to project_path(@vote.project, anchor: "payout-review"), alert: "That rating cannot be flagged right now."
    end
  end
end
