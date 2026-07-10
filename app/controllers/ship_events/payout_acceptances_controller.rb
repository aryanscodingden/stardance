class ShipEvents::PayoutAcceptancesController < ApplicationController
  before_action -> { head :not_found unless Post::ShipEvent.payout_feature_enabled?(current_user) }

  def create
    ship_event = Post::ShipEvent.find(params[:ship_event_id])
    authorize ship_event.project, :accept_payout?

    if ship_event.accept_payout_now(user: current_user)
      track_event "payout_accepted_early", ship_event_id: ship_event.id, project_id: ship_event.project.id
      redirect_to project_path(ship_event.project, anchor: "payout-review"), notice: "Payout accepted and issued."
    else
      redirect_to project_path(ship_event.project, anchor: "payout-review"), alert: "This payout cannot be accepted right now."
    end
  end
end
