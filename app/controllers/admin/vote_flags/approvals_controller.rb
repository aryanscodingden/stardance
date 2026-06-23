class Admin::VoteFlags::ApprovalsController < Admin::ApplicationController
  before_action -> { head :not_found unless Post::ShipEvent.payout_feature_enabled?(current_user) }

  def create
    flag = Vote::Event.pending_vote_flags.find(params[:vote_flag_id])
    authorize flag, :update?

    flag.vote.accept_flag(reviewer: current_user)
    redirect_to admin_vote_flags_path, notice: "Rating discarded and project returned to voting."
  end
end
