class Admin::VoteFlagsController < Admin::ApplicationController
  before_action -> { head :not_found unless Post::ShipEvent.payout_feature_enabled?(current_user) }

  def index
    authorize Vote::Event

    @pagy, @flags = pagy(
      Vote::Event.pending_vote_flags
        .includes(:user, vote: [ :user, :project, :ship_event ])
        .order(created_at: :asc)
    )
  end
end
