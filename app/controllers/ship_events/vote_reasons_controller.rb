class ShipEvents::VoteReasonsController < ApplicationController
  before_action -> { head :not_found unless Post::ShipEvent.payout_feature_enabled?(current_user) }

  def show
    @ship_event = Post::ShipEvent.find(params[:ship_event_id])
    authorize @ship_event, :vote_reasons?

    @votes = @ship_event.votes.payout_countable.order(:created_at)
  end
end
