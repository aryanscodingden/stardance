class Admin::VoteFlags::RejectionsController < Admin::ApplicationController
  before_action -> { head :not_found unless Post::ShipEvent.payout_feature_enabled?(current_user) }

  def create
    flag = Vote::Event.pending_vote_flags.find(params[:vote_flag_id])
    authorize flag, :update?

    flag.vote.reject_flag(reviewer: current_user)
    redirect_to admin_vote_flags_path, notice: "Flag rejected, stardust charged, and payout released if no other flags are pending."
  end
end
