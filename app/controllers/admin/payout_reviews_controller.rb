class Admin::PayoutReviewsController < Admin::ApplicationController
  before_action -> { head :not_found unless Post::ShipEvent.payout_feature_enabled?(current_user) }
  before_action :set_body_class

  def index
    authorize :payout_review

    @sample = Post::ShipEvent.payout_score_sample
    ship_event_previews = Post::ShipEvent.ready_for_payout
                                         .includes(:mission_submission, :votes, post: [ :user, :project ])
                                         .map { |ship_event| [ ship_event, ship_event.payout_preview(@sample) ] }
                                         .sort_by { |(_ship_event, preview)| -preview[:estimated_payout].to_i }

    @pagy, @ship_event_previews = pagy(:offset, ship_event_previews, limit: 25)
  end

  def show
    @ship_event = Post::ShipEvent.includes(:mission_submission, post: [ :user, :project ]).find(params[:id])
    authorize @ship_event, policy_class: Admin::PayoutReviewPolicy

    @preview = @ship_event.payout_preview
    @votes = @ship_event.votes
                        .includes(:user, :events)
                        .order(:created_at)
  end

  private

  def set_body_class
    @body_class = "app-layout-page"
  end
end
